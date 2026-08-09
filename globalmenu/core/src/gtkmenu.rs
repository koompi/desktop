// org.gtk.Menus + org.gtk.Actions client.
//
// GTK hands out subscriptions, not a tree: Start(au) returns flat (group, menu,
// items) triples whose items link other (group, menu) pairs through ":section" and
// ":submenu". Sections splice into the parent with a separator; submenus become
// children. A menubar's top-level entries are almost always pure section links, so
// treating a section as a submenu produces empty or duplicated menus.
//
// Item state - enabled, checkbox, radio - is not in the menu model. It comes from
// org.gtk.Actions.DescribeAll on the group named by the action prefix.

use std::collections::{BTreeSet, HashMap};
use std::rc::Rc;

use zbus::blocking::Connection;
use zbus::zvariant::{OwnedValue, Signature, Value};
use zbus::Message;

use crate::menu::{self, Item, OwnedArg, Table, Target};

pub struct Source {
    pub bus: String,
    pub menu_path: String,
    pub app_path: Option<String>,
    pub win_path: Option<String>,
    /// X11 only, from `_UNITY_OBJECT_PATH`. Wayland-native GTK apps leave it unset.
    pub unity_path: Option<String>,
}

const MAX_DEPTH: usize = 8;

const MENUS: &str = "org.gtk.Menus";
const ACTIONS: &str = "org.gtk.Actions";

type Attrs = HashMap<String, OwnedValue>;
type Described = HashMap<String, (bool, Signature, Vec<OwnedValue>)>;

struct ActionState {
    enabled: bool,
    /// The current state, or none for a stateless action.
    state: Option<OwnedValue>,
}

struct Fetcher<'a> {
    conn: &'a Connection,
    src: &'a Source,
    table: &'a mut Table,
    menus: HashMap<(u32, u32), Rc<Vec<Attrs>>>,
    started: BTreeSet<u32>,
    /// action-group path -> (bare action name -> state). A missing map means the
    /// group did not answer DescribeAll, which is not the same as "the group has
    /// no actions": in that case we must not grey the whole menu out.
    describes: HashMap<String, Option<HashMap<String, ActionState>>>,
}

impl<'a> Fetcher<'a> {
    fn new(conn: &'a Connection, src: &'a Source, table: &'a mut Table) -> Self {
        Self {
            conn,
            src,
            table,
            menus: HashMap::new(),
            started: BTreeSet::new(),
            describes: HashMap::new(),
        }
    }

    fn end_subscriptions(&self) {
        if self.started.is_empty() {
            return;
        }
        let handles: Vec<u32> = self.started.iter().copied().collect();
        let _ = call(|| {
            self.conn.call_method(
                Some(self.src.bus.as_str()),
                self.src.menu_path.as_str(),
                Some(MENUS),
                "End",
                &(handles,),
            )
        });
    }

    /// Subscribes to a group and caches every (group, menu) it returns.
    fn ensure_group(&mut self, group: u32) {
        if !self.started.insert(group) {
            return;
        }
        let reply = call(|| {
            self.conn.call_method(
                Some(self.src.bus.as_str()),
                self.src.menu_path.as_str(),
                Some(MENUS),
                "Start",
                &(vec![group],),
            )
        });
        let Some(reply) = reply else {
            return;
        };
        let Ok(triples) = reply.body().deserialize::<Vec<(u32, u32, Vec<Attrs>)>>() else {
            return;
        };
        // A single Start reply routinely carries menus for groups we did not ask
        // for, so everything in the reply is kept.
        for (group, id, items) in triples {
            self.menus.insert((group, id), Rc::new(items));
        }
    }

    /// DescribeAll for an action-group path, cached. Leaves a missing entry when
    /// the app does not answer, which we read as "assume everything is live".
    fn ensure_describe(&mut self, path: &str) {
        if self.describes.contains_key(path) {
            return;
        }
        let described = call(|| {
            self.conn.call_method(
                Some(self.src.bus.as_str()),
                path,
                Some(ACTIONS),
                "DescribeAll",
                &(),
            )
        })
        .and_then(|reply| reply.body().deserialize::<Described>().ok())
        .map(|described| {
            described
                .into_iter()
                .map(|(name, (enabled, _, state))| {
                    let state = ActionState {
                        enabled,
                        state: state.into_iter().next(),
                    };
                    (name, state)
                })
                .collect()
        });
        self.describes.insert(path.to_owned(), described);
    }

    fn resolve(&mut self, group: u32, id: u32, depth: usize) -> Vec<Item> {
        let mut out = Vec::new();
        if depth >= MAX_DEPTH {
            return out;
        }

        self.ensure_group(group);
        let Some(items) = self.menus.get(&(group, id)).cloned() else {
            return out;
        };

        for attrs in items.iter() {
            if let Some(section) = attrs.get(":section") {
                let Some((group, id)) = pair_of(section) else {
                    continue;
                };
                let section = self.resolve(group, id, depth + 1);
                splice_section(&mut out, section);
                continue;
            }

            let mut item = self.leaf(attrs);
            if let Some((group, id)) = attrs.get(":submenu").and_then(|v| pair_of(v)) {
                item.submenu = true;
                item.children = self.resolve(group, id, depth + 1);
            }
            out.push(item);
        }

        out
    }

    fn leaf(&mut self, attrs: &Attrs) -> Item {
        let label = attrs
            .get("label")
            .and_then(as_str)
            .map(menu::strip_mnemonics)
            .unwrap_or_default();
        let shortcut = attrs
            .get("accel")
            .and_then(as_str)
            .map(menu::pretty_accel)
            .unwrap_or_default();
        let mut item = Item {
            shortcut,
            ..Item::leaf(label)
        };

        let src = self.src;
        let Some(full) = attrs.get("action").and_then(as_str) else {
            return item;
        };
        let Some((prefix, bare)) = full.split_once('.') else {
            return item;
        };
        let Some(group_path) = path_for_prefix(src, prefix) else {
            return item;
        };

        let target = attrs.get("target").map(|v| &**v);

        self.ensure_describe(group_path);
        if let Some(Some(states)) = self.describes.get(group_path) {
            match states.get(bare) {
                Some(action) => {
                    item.enabled = action.enabled;
                    if let Some(state) = &action.state {
                        apply_state(&mut item, state, target);
                    }
                }
                // The model advertises an action the group does not implement.
                // Showing it live would be a lie; show it greyed out.
                None => item.enabled = false,
            }
        }

        item.id = self.table.add(Target::Gtk {
            bus: src.bus.clone(),
            path: group_path.to_owned(),
            action: bare.to_owned(),
            arg: target.and_then(owned_arg),
        });
        item
    }
}

/// The action group an action prefix names. A prefix the application invented,
/// or one whose path this window never published, lands on "no group, no id":
/// the item still renders, it just cannot be activated.
fn path_for_prefix<'a>(src: &'a Source, prefix: &str) -> Option<&'a str> {
    match prefix {
        "app" => src.app_path.as_deref(),
        "win" => src.win_path.as_deref(),
        "unity" => src.unity_path.as_deref(),
        _ => None,
    }
}

/// A section splices into its parent, separated from what came before it.
fn splice_section(out: &mut Vec<Item>, section: Vec<Item>) {
    if section.is_empty() {
        return;
    }
    if !out.is_empty() {
        out.push(Item::separator());
    }
    out.extend(section);
}

/// A boolean state is a checkbox; a state that matches the item's target is a
/// selected radio entry. Anything else carries no visual meaning.
fn apply_state(item: &mut Item, state: &Value, target: Option<&Value>) {
    if let Value::Bool(checked) = state {
        item.toggle = true;
        item.checked = *checked;
        return;
    }
    if let (Value::Str(state), Some(Value::Str(target))) = (state, target) {
        item.toggle = true;
        item.checked = state == target;
    }
}

fn as_str(value: &OwnedValue) -> Option<&str> {
    match &**value {
        Value::Str(s) => Some(s.as_str()),
        _ => None,
    }
}

fn pair_of(value: &Value) -> Option<(u32, u32)> {
    let Value::Structure(fields) = value else {
        return None;
    };
    match fields.fields() {
        [Value::U32(group), Value::U32(id)] => Some((*group, *id)),
        _ => None,
    }
}

/// Only the shapes the activation table can round-trip; anything else is dropped
/// rather than guessed at.
fn owned_arg(value: &Value) -> Option<OwnedArg> {
    match value {
        Value::Str(s) => Some(OwnedArg::Str(s.to_string())),
        Value::I32(v) => Some(OwnedArg::I32(*v)),
        Value::U32(v) => Some(OwnedArg::U32(*v)),
        Value::Bool(v) => Some(OwnedArg::Bool(*v)),
        Value::F64(v) => Some(OwnedArg::F64(*v)),
        _ => None,
    }
}

fn value_of(arg: &OwnedArg) -> Value<'static> {
    match arg {
        OwnedArg::Str(s) => Value::Str(s.clone().into()),
        OwnedArg::I32(v) => Value::I32(*v),
        OwnedArg::U32(v) => Value::U32(*v),
        OwnedArg::Bool(v) => Value::Bool(*v),
        OwnedArg::F64(v) => Value::F64(*v),
    }
}

/// A blocking call that swallows D-Bus errors: every caller here treats "the app
/// did not answer" the same as "the app has no menu".
///
/// The timeout is the connection's, set once by whoever builds it (see
/// `dbusmenu::connect`), not per call, so the zig daemon's 2000 ms subscription
/// and 3000 ms activation budgets collapse into one.
fn call(method: impl FnOnce() -> zbus::Result<Message>) -> Option<Message> {
    method().ok()
}

/// Fetches the menubar rooted at (group 0, menu 0) and fills `table` with the
/// activation targets for every actionable entry.
pub fn fetch(conn: &Connection, src: &Source, table: &mut Table) -> Vec<Item> {
    let mut fetcher = Fetcher::new(conn, src, table);
    let items = fetcher.resolve(0, 0, 0);
    fetcher.end_subscriptions();
    menu::tidy(items)
}

/// Invokes an action on its group.
pub fn activate(conn: &Connection, bus: &str, path: &str, action: &str, arg: Option<&OwnedArg>) {
    let args: Vec<Value<'_>> = arg.map(value_of).into_iter().collect();
    let platform_data: HashMap<String, Value<'_>> = HashMap::new();
    let _ = call(|| {
        conn.call_method(
            Some(bus),
            path,
            Some(ACTIONS),
            "Activate",
            &(action, args, platform_data),
        )
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::Structure;

    fn source() -> Source {
        Source {
            bus: ":1.42".into(),
            menu_path: "/org/gtk/menus/menubar".into(),
            app_path: Some("/org/app".into()),
            win_path: Some("/org/app/window/1".into()),
            unity_path: None,
        }
    }

    #[test]
    fn prefixes_pick_their_action_group() {
        let src = source();
        assert_eq!(path_for_prefix(&src, "app"), Some("/org/app"));
        assert_eq!(path_for_prefix(&src, "win"), Some("/org/app/window/1"));
        assert_eq!(path_for_prefix(&src, "unity"), None);
        assert_eq!(path_for_prefix(&src, "made-up"), None);
    }

    // An X11 app that published _UNITY_OBJECT_PATH must get activatable items,
    // not just rendered ones. x11.rs reads the property; dropping it here was
    // what made the menu look right and do nothing.
    #[test]
    fn unity_resolves_when_the_window_published_a_path() {
        let src = Source {
            unity_path: Some("/com/canonical/unity/1".into()),
            ..source()
        };
        assert_eq!(path_for_prefix(&src, "unity"), Some("/com/canonical/unity/1"));
    }

    #[test]
    fn a_prefix_without_a_path_has_no_group() {
        let src = Source {
            win_path: None,
            ..source()
        };
        assert_eq!(path_for_prefix(&src, "win"), None);
    }

    #[test]
    fn targets_map_to_the_shapes_the_table_can_round_trip() {
        assert_eq!(
            owned_arg(&Value::from("dark")),
            Some(OwnedArg::Str("dark".into()))
        );
        assert_eq!(owned_arg(&Value::I32(-3)), Some(OwnedArg::I32(-3)));
        assert_eq!(owned_arg(&Value::U32(3)), Some(OwnedArg::U32(3)));
        assert_eq!(owned_arg(&Value::Bool(true)), Some(OwnedArg::Bool(true)));
        assert_eq!(owned_arg(&Value::F64(1.5)), Some(OwnedArg::F64(1.5)));
    }

    #[test]
    fn an_unrepresentable_target_is_dropped() {
        assert_eq!(owned_arg(&Value::U16(1)), None);
        assert_eq!(
            owned_arg(&Value::Structure(Structure::from((1u32, 2u32)))),
            None
        );
    }

    #[test]
    fn menu_links_must_be_a_group_menu_pair() {
        let pair = Value::Structure(Structure::from((3u32, 7u32)));
        assert_eq!(pair_of(&pair), Some((3, 7)));
        assert_eq!(pair_of(&Value::U32(3)), None);
        assert_eq!(
            pair_of(&Value::Structure(Structure::from((3u32, 7u32, 9u32)))),
            None
        );
    }

    #[test]
    fn a_boolean_state_is_a_checkbox() {
        let mut item = Item::leaf("Toolbar");
        apply_state(&mut item, &Value::Bool(true), None);
        assert!(item.toggle);
        assert!(item.checked);
    }

    #[test]
    fn a_string_state_checks_only_the_matching_radio_entry() {
        let state = Value::from("dark");

        let mut selected = Item::leaf("Dark");
        apply_state(&mut selected, &state, Some(&Value::from("dark")));
        assert!(selected.toggle);
        assert!(selected.checked);

        let mut other = Item::leaf("Light");
        apply_state(&mut other, &state, Some(&Value::from("light")));
        assert!(other.toggle);
        assert!(!other.checked);
    }

    #[test]
    fn a_state_with_no_visual_meaning_leaves_the_item_alone() {
        let mut item = Item::leaf("Zoom");
        apply_state(&mut item, &Value::from("dark"), None);
        apply_state(&mut item, &Value::U32(1), Some(&Value::U32(1)));
        assert!(!item.toggle);
        assert!(!item.checked);
    }

    #[test]
    fn sections_splice_in_with_a_separator_between_them() {
        let mut out = Vec::new();
        splice_section(&mut out, vec![Item::leaf("New"), Item::leaf("Open")]);
        splice_section(&mut out, vec![]);
        splice_section(&mut out, vec![Item::leaf("Quit")]);

        let labels: Vec<&str> = out.iter().map(|i| i.label.as_str()).collect();
        assert_eq!(labels, ["New", "Open", "", "Quit"]);
        assert!(out[2].separator);
        assert!(out.iter().all(|i| i.children.is_empty()));
    }

    #[test]
    fn the_first_section_does_not_open_with_a_separator() {
        let mut out = Vec::new();
        splice_section(&mut out, vec![Item::leaf("New")]);
        assert_eq!(out.len(), 1);
        assert!(!out[0].separator);
    }
}
