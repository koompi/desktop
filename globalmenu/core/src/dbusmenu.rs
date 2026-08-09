// com.canonical.dbusmenu client. The application exports its menubar as a tree of
// numbered nodes; a click travels back as Event(id, "clicked", ...). Apps find us
// through the AppMenu registrar.


use zbus::blocking::Connection;
use zbus::zvariant::{Array, Dict, Structure, Value};
use zbus::Message;

use crate::menu::{self, Item, Table, Target};

pub struct Source {
    pub bus: String,
    pub path: String,
}

const IFACE: &str = "com.canonical.dbusmenu";
const MAX_DEPTH: usize = 8;

const WANTED_PROPS: [&str; 8] = [
    "label",
    "enabled",
    "visible",
    "type",
    "children-display",
    "toggle-type",
    "toggle-state",
    "shortcut",
];

pub fn fetch(conn: &Connection, src: &Source, table: &mut Table) -> Vec<Item> {
    fetch_from(conn, src, table, 0)
}

/// GetLayout on `parent`, returning the parsed children.
pub fn fetch_from(conn: &Connection, src: &Source, table: &mut Table, parent: i32) -> Vec<Item> {
    // Ask the app to populate the subtree first. Qt apps build menus lazily and
    // only settle their enabled states here.
    about_to_show(conn, src, parent);

    let owner = conn.clone();
    let (bus, path) = (src.bus.clone(), src.path.clone());
    let reply = call(move || {
        owner.call_method(
            Some(bus.as_str()),
            path.as_str(),
            Some(IFACE),
            "GetLayout",
            &(parent, -1i32, &WANTED_PROPS[..]),
        )
    });

    let Some(reply) = reply else {
        return Vec::new();
    };
    let body = reply.body();
    let Ok(layout) = body.deserialize::<Structure<'_>>() else {
        return Vec::new();
    };
    parse_layout(&layout, src, table)
}

pub fn about_to_show(conn: &Connection, src: &Source, id: i32) {
    let owner = conn.clone();
    let (bus, path) = (src.bus.clone(), src.path.clone());
    let _ = call(move || {
        owner.call_method(
            Some(bus.as_str()),
            path.as_str(),
            Some(IFACE),
            "AboutToShow",
            &(id,),
        )
    });
}

/// Sends a dbusmenu event. `kind` is "clicked", "opened" or "closed".
pub fn event(conn: &Connection, bus: &str, path: &str, id: i32, kind: &str) {
    let owner = conn.clone();
    let (bus, path, kind) = (bus.to_owned(), path.to_owned(), kind.to_owned());
    let _ = call(move || {
        owner.call_method(
            Some(bus.as_str()),
            path.as_str(),
            Some(IFACE),
            "Event",
            &(id, kind.as_str(), Value::I32(0), 0u32),
        )
    });
}

/// A blocking call that swallows D-Bus errors: every caller here treats "the app
/// did not answer" the same as "the app has no menu".
///
/// The timeout is the connection's, set once by whoever builds it (see
/// `connect()`), not per call. A thread per call would express the zig daemon's
/// 3000/2000 ms split exactly, but it leaks one thread per focus change against
/// an application that never answers, and this daemon runs all session.
fn call(method: impl FnOnce() -> zbus::Result<Message>) -> Option<Message> {
    method().ok()
}

/// Walks the `(u(ia{sv}av))` GetLayout reply from the root node's children down.
fn parse_layout(layout: &Structure<'_>, src: &Source, table: &mut Table) -> Vec<Item> {
    let Some(Value::Structure(root)) = layout.fields().get(1) else {
        return Vec::new();
    };
    let Some(Value::Array(kids)) = root.fields().get(2) else {
        return Vec::new();
    };
    let mut fetcher = Fetcher { src, table };
    menu::tidy(fetcher.child_list(kids, 0))
}

struct Fetcher<'a> {
    src: &'a Source,
    table: &'a mut Table,
}

impl Fetcher<'_> {
    /// Parses one (ia{sv}av) node into an item plus its children.
    fn node(&mut self, n: &Value<'_>, depth: usize) -> Option<Item> {
        let Value::Structure(node) = unbox(n) else {
            return None;
        };
        let fields = node.fields();
        if fields.len() < 3 {
            return None;
        }
        let &Value::I32(item_id) = &fields[0] else {
            return None;
        };
        let Value::Dict(props) = &fields[1] else {
            return None;
        };

        let mut item = item_from_props(props)?;

        if !item.separator {
            item.id = self.table.add(Target::DBusMenu {
                bus: self.src.bus.clone(),
                path: self.src.path.clone(),
                item_id,
            });
        }

        if depth < MAX_DEPTH {
            if let Value::Array(kids) = &fields[2] {
                item.children = self.child_list(kids, depth + 1);
            }
        }
        Some(item)
    }

    fn child_list(&mut self, kids: &Array<'_>, depth: usize) -> Vec<Item> {
        kids.iter().filter_map(|k| self.node(k, depth)).collect()
    }
}

fn item_from_props(props: &Dict<'_, '_>) -> Option<Item> {
    if !bool_prop(props, "visible", true) {
        return None;
    }

    let mut item = Item {
        label: menu::strip_mnemonics(str_prop(props, "label").unwrap_or_default()),
        shortcut: shortcut_of(props),
        enabled: bool_prop(props, "enabled", true),
        ..Item::default()
    };

    if str_prop(props, "type") == Some("separator") {
        item.separator = true;
        item.enabled = false;
    }

    // Qt only fills a submenu in on AboutToShow, so "children-display" is the
    // only sign that an item opens one until the user does.
    if str_prop(props, "children-display") == Some("submenu") {
        item.submenu = true;
    }

    if str_prop(props, "toggle-type").is_some_and(|t| !t.is_empty()) {
        item.toggle = true;
        item.checked = i32_prop(props, "toggle-state") == Some(1);
    }

    Some(item)
}

fn shortcut_of(props: &Dict<'_, '_>) -> String {
    // aas: a list of key sequences; the menu shows the first.
    let Some(Value::Array(sequences)) = prop(props, "shortcut") else {
        return String::new();
    };
    let Some(Value::Array(keys)) = sequences.first().map(unbox) else {
        return String::new();
    };
    render_shortcut(keys.iter().filter_map(|k| match unbox(k) {
        Value::Str(s) => Some(s.as_str()),
        _ => None,
    }))
}

fn render_shortcut<'a>(keys: impl Iterator<Item = &'a str>) -> String {
    let mut out = String::new();
    for key in keys {
        if !out.is_empty() {
            out.push('+');
        }
        if key.eq_ignore_ascii_case("control") {
            out.push_str("Ctrl");
        } else if key.len() == 1 {
            out.push_str(&key.to_ascii_uppercase());
        } else {
            out.push_str(key);
        }
    }
    out
}

fn prop<'d, 'k, 'v>(props: &'d Dict<'k, 'v>, key: &str) -> Option<&'d Value<'v>> {
    props.iter().find_map(|(k, v)| match k {
        Value::Str(s) if s.as_str() == key => Some(unbox(v)),
        _ => None,
    })
}

fn str_prop<'d>(props: &'d Dict<'_, '_>, key: &str) -> Option<&'d str> {
    match prop(props, key)? {
        Value::Str(s) => Some(s.as_str()),
        _ => None,
    }
}

fn bool_prop(props: &Dict<'_, '_>, key: &str, default: bool) -> bool {
    match prop(props, key) {
        Some(&Value::Bool(b)) => b,
        _ => default,
    }
}

fn i32_prop(props: &Dict<'_, '_>, key: &str) -> Option<i32> {
    match prop(props, key)? {
        &Value::I32(i) => Some(i),
        _ => None,
    }
}

/// Unwraps a `v` box; returns the value itself otherwise.
fn unbox<'d, 'v>(v: &'d Value<'v>) -> &'d Value<'v> {
    match v {
        Value::Value(inner) => inner,
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use zbus::zvariant::serialized::Context;
    use zbus::zvariant::{to_bytes, Endian, Structure as Struct};

    type Props = HashMap<String, Value<'static>>;
    type Node = (i32, Props, Vec<Value<'static>>);

    fn props(pairs: &[(&str, Value<'static>)]) -> Props {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.try_clone().unwrap()))
            .collect()
    }

    fn node(id: i32, pairs: &[(&str, Value<'static>)], kids: Vec<Value<'static>>) -> Value<'static> {
        Value::from(Struct::from((id, props(pairs), kids)))
    }

    /// Runs the real GetLayout reply path: the tree is serialised in D-Bus format
    /// and parsed back exactly as a reply body is.
    fn parse(children: Vec<Value<'static>>) -> (Vec<Item>, Table) {
        let root: Node = (0, Props::new(), children);
        let data = to_bytes(Context::new_dbus(Endian::Little, 0), &(0u32, root)).unwrap();
        let (layout, _): (Structure<'_>, _) = data
            .deserialize_for_dynamic_signature("(u(ia{sv}av))")
            .unwrap();

        let src = Source {
            bus: ":1.42".into(),
            path: "/MenuBar".into(),
        };
        let mut table = Table::new();
        let items = parse_layout(&layout, &src, &mut table);
        (items, table)
    }

    #[test]
    fn renders_only_the_first_key_sequence() {
        let shortcut = Value::from(vec![vec!["Control", "q"], vec!["F4"]]);
        let (items, _) = parse(vec![node(1, &[("shortcut", shortcut)], vec![])]);
        assert_eq!(items[0].shortcut, "Ctrl+Q");
    }

    #[test]
    fn render_shortcut_upcases_single_keys_and_passes_the_rest_through() {
        for (keys, want) in [
            (vec!["Control", "s"], "Ctrl+S"),
            (vec!["CONTROL", "Shift", "z"], "Ctrl+Shift+Z"),
            (vec!["Alt", "F4"], "Alt+F4"),
            (vec![], ""),
        ] {
            assert_eq!(render_shortcut(keys.iter().copied()), want, "{keys:?}");
        }
    }

    #[test]
    fn invisible_nodes_take_their_children_with_them() {
        let hidden = node(
            1,
            &[("label", "Gone".into()), ("visible", false.into())],
            vec![node(2, &[("label", "Child".into())], vec![])],
        );
        let (items, table) = parse(vec![hidden, node(3, &[("label", "Kept".into())], vec![])]);

        assert_eq!(items.len(), 1);
        assert_eq!(items[0].label, "Kept");
        assert_eq!(table.len(), 1);
    }

    #[test]
    fn separators_are_disabled_and_get_no_activation_id() {
        let (items, table) = parse(vec![
            node(1, &[("label", "New".into())], vec![]),
            node(2, &[("type", "separator".into())], vec![]),
            node(3, &[("label", "Quit".into())], vec![]),
        ]);

        assert!(items[1].separator);
        assert!(!items[1].enabled);
        assert_eq!(items[1].id, 0);
        assert_eq!(table.len(), 2);
    }

    #[test]
    fn disabled_items_still_get_an_id() {
        let (items, table) = parse(vec![node(
            7,
            &[("label", "Paste".into()), ("enabled", false.into())],
            vec![],
        )]);

        assert!(!items[0].enabled);
        assert_eq!(items[0].id, 1);
        assert!(matches!(table.get(1), Some(Target::DBusMenu { item_id: 7, .. })));
    }

    #[test]
    fn a_childless_submenu_is_known_from_children_display() {
        let (items, _) = parse(vec![
            node(
                1,
                &[("label", "Tools".into()), ("children-display", "submenu".into())],
                vec![],
            ),
            node(
                2,
                &[("label", "Recent".into())],
                vec![node(3, &[("label", "a.txt".into())], vec![])],
            ),
        ]);

        assert!(items[0].submenu);
        assert!(items[0].children.is_empty());
        assert!(!items[1].submenu, "children alone must not imply a submenu");
    }

    #[test]
    fn toggles_read_their_state() {
        let (items, _) = parse(vec![
            node(
                1,
                &[
                    ("label", "Bold".into()),
                    ("toggle-type", "checkmark".into()),
                    ("toggle-state", 1i32.into()),
                ],
                vec![],
            ),
            node(
                2,
                &[
                    ("label", "Italic".into()),
                    ("toggle-type", "checkmark".into()),
                    ("toggle-state", 0i32.into()),
                ],
                vec![],
            ),
            node(3, &[("label", "Plain".into()), ("toggle-type", "".into())], vec![]),
        ]);

        assert!(items[0].toggle && items[0].checked);
        assert!(items[1].toggle && !items[1].checked);
        assert!(!items[2].toggle);
    }

    #[test]
    fn labels_lose_their_mnemonic_markers() {
        let (items, _) = parse(vec![node(1, &[("label", "_File".into())], vec![])]);
        assert_eq!(items[0].label, "File");
    }

    #[test]
    fn missing_and_mistyped_properties_fall_back() {
        let (items, _) = parse(vec![node(
            1,
            &[("label", 42i32.into()), ("enabled", "yes".into())],
            vec![],
        )]);

        assert_eq!(items[0].label, "");
        assert!(items[0].enabled);
        assert_eq!(items[0].shortcut, "");
    }

    #[test]
    fn recursion_stops_at_the_depth_cap_but_keeps_the_item() {
        let mut deepest = node(100, &[("label", "deepest".into())], vec![]);
        for i in (0..MAX_DEPTH + 1).rev() {
            deepest = node(i as i32, &[("label", format!("d{i}").into())], vec![deepest]);
        }

        let (items, _) = parse(vec![deepest]);

        let mut level = &items[0];
        let mut depth = 0;
        while let Some(child) = level.children.first() {
            level = child;
            depth += 1;
        }
        assert_eq!(depth, MAX_DEPTH);
        assert_eq!(level.label, format!("d{MAX_DEPTH}"));
    }

    #[test]
    fn leading_and_doubled_separators_are_tidied_away() {
        let (items, _) = parse(vec![
            node(1, &[("type", "separator".into())], vec![]),
            node(2, &[("label", "Open".into())], vec![]),
            node(3, &[("type", "separator".into())], vec![]),
            node(4, &[("type", "separator".into())], vec![]),
            node(5, &[("label", "Quit".into())], vec![]),
            node(6, &[("type", "separator".into())], vec![]),
        ]);

        assert_eq!(items.len(), 3);
        assert_eq!(items[0].label, "Open");
        assert!(items[1].separator);
        assert_eq!(items[2].label, "Quit");
    }
}
