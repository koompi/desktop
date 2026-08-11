//! D05: an async `com.canonical.dbusmenu` client.
//!
//! The application exports its menu as a tree of numbered nodes and hands the whole thing
//! over in one `GetLayout` reply whose signature `zvariant` cannot pick a static type for.
//! `globalmenu/core/src/dbusmenu.rs` solved that once against real bytes and this follows
//! it: deserialise the reply body as a [`Structure`] and walk it. The differences are that
//! this one is async, and that it decides nothing on the consumer's behalf. Invisible items
//! and separators are reported, not dropped, and labels keep their mnemonic markers.

use koompi_service::{Error, Result};
use zbus::Connection;
use zvariant::{Array, Dict, Structure, Value};

pub(crate) const IFACE: &str = "com.canonical.dbusmenu";

/// Deep enough for any real menu, and a bound on a tree an application could otherwise
/// make cyclic. The item at the cap is kept; only its children are not walked.
const MAX_DEPTH: usize = 8;

const WANTED_PROPS: [&str; 8] = [
    "label",
    "enabled",
    "visible",
    "type",
    "children-display",
    "toggle-type",
    "toggle-state",
    "icon-name",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ToggleType {
    None,
    Checkmark,
    Radio,
    Other(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToggleState {
    Off,
    On,
    /// The spec's third state, and also what an item that never set one reports.
    Indeterminate,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MenuItem {
    pub id: i32,
    pub label: String,
    pub enabled: bool,
    /// Reported rather than acted on. A host that hides its own entries by flipping this
    /// still expects the panel to have been told.
    pub visible: bool,
    pub separator: bool,
    pub icon_name: String,
    pub toggle_type: ToggleType,
    pub toggle_state: ToggleState,
    /// Qt fills a submenu in only on `AboutToShow`, so this is the only sign an item opens
    /// one until somebody asks.
    pub has_submenu: bool,
    pub children: Vec<MenuItem>,
}

impl Default for MenuItem {
    fn default() -> Self {
        Self {
            id: 0,
            label: String::new(),
            enabled: true,
            visible: true,
            separator: false,
            icon_name: String::new(),
            toggle_type: ToggleType::None,
            toggle_state: ToggleState::Indeterminate,
            has_submenu: false,
            children: Vec::new(),
        }
    }
}

impl MenuItem {
    /// Depth-first walk including this node, for a consumer that needs to find an id.
    pub fn walk(&self) -> Vec<&MenuItem> {
        let mut found = vec![self];
        for child in &self.children {
            found.extend(child.walk());
        }
        found
    }
}

/// `AboutToShow` first, the way a real panel does before it draws: Qt applications build
/// their submenus lazily and only settle the enabled states there. It is a read, and an
/// application that does not implement it is not an error.
pub(crate) async fn layout(
    conn: &Connection,
    service: &str,
    path: &str,
    parent: i32,
) -> Result<MenuItem> {
    let _ = about_to_show(conn, service, path, parent).await;

    let reply = conn
        .call_method(
            Some(service),
            path,
            Some(IFACE),
            "GetLayout",
            &(parent, -1i32, &WANTED_PROPS[..]),
        )
        .await?;

    decode(reply.body().data().bytes())
}

/// Split out so the test can hand it bytes captured off this machine instead of a bus.
pub(crate) fn decode(body: &[u8]) -> Result<MenuItem> {
    let context = zvariant::serialized::Context::new_dbus(zvariant::Endian::Little, 0);
    let data = zvariant::serialized::Data::new(body, context);
    let (layout, _): (Structure<'_>, _) = data
        .deserialize_for_dynamic_signature("(u(ia{sv}av))")
        .map_err(|error| Error::Protocol(format!("GetLayout reply: {error}")))?;

    let root = layout
        .fields()
        .get(1)
        .ok_or_else(|| Error::Protocol("GetLayout reply carries no root node".into()))?;

    node(root, 0).ok_or_else(|| Error::Protocol("GetLayout root node is malformed".into()))
}

/// True when the application rebuilt the subtree and the caller should read it again.
pub(crate) async fn about_to_show(
    conn: &Connection,
    service: &str,
    path: &str,
    id: i32,
) -> Result<bool> {
    let reply = conn
        .call_method(Some(service), path, Some(IFACE), "AboutToShow", &(id,))
        .await?;
    Ok(reply.body().deserialize().unwrap_or(false))
}

/// `kind` is "clicked", "hovered", "opened" or "closed". This is the one call in the menu
/// client that an application acts on, so nothing here fires it by itself.
pub(crate) async fn event(
    conn: &Connection,
    service: &str,
    path: &str,
    id: i32,
    kind: &str,
    timestamp: u32,
) -> Result<()> {
    conn.call_method(
        Some(service),
        path,
        Some(IFACE),
        "Event",
        &(id, kind, Value::I32(0), timestamp),
    )
    .await?;
    Ok(())
}

/// One `(ia{sv}av)` node and, to the depth cap, its children.
fn node(value: &Value<'_>, depth: usize) -> Option<MenuItem> {
    let Value::Structure(fields) = unbox(value) else {
        return None;
    };
    let fields = fields.fields();
    let (&Value::I32(id), Value::Dict(props)) = (fields.first()?, fields.get(1)?) else {
        return None;
    };

    let mut item = from_props(id, props);
    if depth < MAX_DEPTH {
        if let Some(Value::Array(children)) = fields.get(2) {
            item.children = child_list(children, depth + 1);
        }
    }
    Some(item)
}

fn child_list(children: &Array<'_>, depth: usize) -> Vec<MenuItem> {
    children.iter().filter_map(|c| node(c, depth)).collect()
}

fn from_props(id: i32, props: &Dict<'_, '_>) -> MenuItem {
    let separator = str_prop(props, "type") == Some("separator");
    MenuItem {
        id,
        label: str_prop(props, "label").unwrap_or_default().to_owned(),
        // A separator is never clickable however the application labelled it.
        enabled: bool_prop(props, "enabled", true) && !separator,
        visible: bool_prop(props, "visible", true),
        separator,
        icon_name: str_prop(props, "icon-name").unwrap_or_default().to_owned(),
        toggle_type: match str_prop(props, "toggle-type") {
            None | Some("") => ToggleType::None,
            Some("checkmark") => ToggleType::Checkmark,
            Some("radio") => ToggleType::Radio,
            Some(other) => ToggleType::Other(other.to_owned()),
        },
        toggle_state: match i32_prop(props, "toggle-state") {
            Some(0) => ToggleState::Off,
            Some(1) => ToggleState::On,
            _ => ToggleState::Indeterminate,
        },
        has_submenu: str_prop(props, "children-display") == Some("submenu"),
        children: Vec::new(),
    }
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
fn unbox<'d, 'v>(value: &'d Value<'v>) -> &'d Value<'v> {
    match value {
        Value::Value(inner) => inner,
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use zvariant::serialized::Context;
    use zvariant::{to_bytes, Endian};

    type Props = HashMap<String, Value<'static>>;

    /// The `GetLayout` reply Telegram Desktop gave this machine, byte for byte off the
    /// bus. `cargo run -p koompi-tray --example demo -- capture TelegramDesktop <file>`
    /// wrote it; `busctl call ... GetLayout` shows the same tree.
    const TELEGRAM: &[u8] = include_bytes!("../tests/data/telegram-getlayout.bin");

    fn props(pairs: &[(&str, Value<'static>)]) -> Props {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), v.try_clone().unwrap()))
            .collect()
    }

    fn node_value(
        id: i32,
        pairs: &[(&str, Value<'static>)],
        children: Vec<Value<'static>>,
    ) -> Value<'static> {
        Value::from(Structure::from((id, props(pairs), children)))
    }

    /// Serialises a tree the way an application's reply body is laid out, so the decode
    /// under test is the one that runs against a real bus.
    fn parse(children: Vec<Value<'static>>) -> MenuItem {
        let root = (0i32, Props::new(), children);
        let body = to_bytes(Context::new_dbus(Endian::Little, 0), &(1u32, root)).unwrap();
        decode(body.bytes()).unwrap()
    }

    #[test]
    fn the_captured_telegram_reply_decodes_to_the_tree_busctl_shows() {
        let root = decode(TELEGRAM).unwrap();

        assert_eq!(root.id, 0);
        assert!(root.has_submenu, "the root node carries children-display");

        let leaves: Vec<(i32, &str)> = root
            .children
            .iter()
            .map(|child| (child.id, child.label.as_str()))
            .collect();
        assert_eq!(
            leaves,
            [
                (3, "Open Telegram"),
                (2, "Enable notifications"),
                (1, "Quit Telegram"),
            ]
        );

        assert!(root
            .children
            .iter()
            .all(|child| child.enabled && child.visible && !child.separator && !child.has_submenu));
        // Telegram sets no toggle on any of the three, so the decode must not invent one.
        assert!(root
            .children
            .iter()
            .all(|child| child.toggle_type == ToggleType::None
                && child.toggle_state == ToggleState::Indeterminate));
        assert_eq!(root.walk().len(), 4);
    }

    #[test]
    fn an_invisible_item_is_reported_rather_than_dropped() {
        let root = parse(vec![
            node_value(1, &[("label", "Gone".into()), ("visible", false.into())], vec![]),
            node_value(2, &[("label", "Kept".into())], vec![]),
        ]);

        assert_eq!(root.children.len(), 2);
        assert!(!root.children[0].visible);
        assert!(root.children[1].visible);
    }

    #[test]
    fn a_separator_is_never_enabled_however_it_was_labelled() {
        let root = parse(vec![node_value(
            2,
            &[("type", "separator".into()), ("enabled", true.into())],
            vec![],
        )]);

        assert!(root.children[0].separator);
        assert!(!root.children[0].enabled);
    }

    #[test]
    fn a_childless_submenu_is_known_from_children_display() {
        let root = parse(vec![
            node_value(
                1,
                &[("children-display", "submenu".into())],
                vec![],
            ),
            node_value(
                2,
                &[("label", "Recent".into())],
                vec![node_value(3, &[("label", "a.txt".into())], vec![])],
            ),
        ]);

        assert!(root.children[0].has_submenu);
        assert!(root.children[0].children.is_empty());
        assert!(
            !root.children[1].has_submenu,
            "children alone must not imply a submenu"
        );
    }

    #[test]
    fn toggles_carry_their_type_and_their_third_state() {
        let root = parse(vec![
            node_value(
                1,
                &[
                    ("toggle-type", "checkmark".into()),
                    ("toggle-state", 1i32.into()),
                ],
                vec![],
            ),
            node_value(
                2,
                &[("toggle-type", "radio".into()), ("toggle-state", 0i32.into())],
                vec![],
            ),
            node_value(3, &[("toggle-type", "checkmark".into())], vec![]),
            node_value(4, &[("label", "Plain".into())], vec![]),
        ]);

        assert_eq!(root.children[0].toggle_type, ToggleType::Checkmark);
        assert_eq!(root.children[0].toggle_state, ToggleState::On);
        assert_eq!(root.children[1].toggle_type, ToggleType::Radio);
        assert_eq!(root.children[1].toggle_state, ToggleState::Off);
        assert_eq!(root.children[2].toggle_state, ToggleState::Indeterminate);
        assert_eq!(root.children[3].toggle_type, ToggleType::None);
    }

    #[test]
    fn missing_and_mistyped_properties_fall_back() {
        let root = parse(vec![node_value(
            1,
            &[("label", 42i32.into()), ("enabled", "yes".into())],
            vec![],
        )]);

        let item = &root.children[0];
        assert_eq!(item.label, "");
        assert!(item.enabled);
        assert!(item.visible);
    }

    #[test]
    fn recursion_stops_at_the_depth_cap_but_keeps_the_item_there() {
        let mut deepest = node_value(100, &[("label", "deepest".into())], vec![]);
        for level in (0..MAX_DEPTH + 1).rev() {
            deepest = node_value(
                level as i32,
                &[("label", format!("d{level}").into())],
                vec![deepest],
            );
        }

        let root = parse(vec![deepest]);

        let mut item = &root.children[0];
        let mut depth = 0;
        while let Some(child) = item.children.first() {
            item = child;
            depth += 1;
        }
        // The root node itself costs one level of the cap.
        assert_eq!(depth, MAX_DEPTH - 1);
        assert_eq!(item.label, format!("d{}", MAX_DEPTH - 1));
    }

    #[test]
    fn a_reply_that_is_not_a_layout_is_a_protocol_error_not_a_panic() {
        let body = to_bytes(Context::new_dbus(Endian::Little, 0), &(1u32, "not a node")).unwrap();
        assert!(decode(body.bytes()).is_err());
        assert!(decode(&[]).is_err());
    }
}
