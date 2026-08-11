//! `org.kde.StatusNotifierItem` as plain data.

use std::collections::HashMap;

use zvariant::{OwnedValue, Value};

pub(crate) type Props = HashMap<String, OwnedValue>;

/// Where an item lives: the connection that exports it and the object on it.
///
/// A watcher hands its list out as one string per item, and there are two forms in the
/// wild. KDE's own watcher stores `":1.70/StatusNotifierItem"`; an application that
/// registered a well-known name instead is stored bare, and the object path is then the
/// spec's default.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ItemAddress {
    pub service: String,
    pub path: String,
}

const DEFAULT_ITEM_PATH: &str = "/StatusNotifierItem";

impl ItemAddress {
    pub fn parse(registered: &str) -> Option<Self> {
        let registered = registered.trim();
        if registered.is_empty() || registered.starts_with('/') {
            return None;
        }
        Some(match registered.find('/') {
            Some(cut) => Self {
                service: registered[..cut].to_owned(),
                path: registered[cut..].to_owned(),
            },
            None => Self {
                service: registered.to_owned(),
                path: DEFAULT_ITEM_PATH.to_owned(),
            },
        })
    }

    /// `RegisterStatusNotifierItem` takes either a bus name or an object path, and when it
    /// is a path the item is on the caller's own connection. Only the sender is trusted
    /// for that case: an application may not register an object it does not export.
    pub fn from_registration(argument: &str, sender: &str) -> Option<Self> {
        let argument = argument.trim();
        if argument.starts_with('/') {
            return Some(Self {
                service: sender.to_owned(),
                path: argument.to_owned(),
            });
        }
        Self::parse(argument)
    }

    /// The form a watcher publishes and a consumer keys on.
    pub fn key(&self) -> String {
        format!("{}{}", self.service, self.path)
    }
}

/// Raw as received: ARGB32, network byte order, the application's own dimensions. Turning
/// this into a texture is the consumer's job and needs a toolkit, which this crate has
/// none of by rule.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pixmap {
    pub width: i32,
    pub height: i32,
    pub argb32: Vec<u8>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ToolTip {
    pub icon_name: String,
    pub icon_pixmap: Vec<Pixmap>,
    pub title: String,
    pub description: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    Passive,
    Active,
    NeedsAttention,
    Other(String),
}

impl Status {
    pub fn as_str(&self) -> &str {
        match self {
            Self::Passive => "Passive",
            Self::Active => "Active",
            Self::NeedsAttention => "NeedsAttention",
            Self::Other(raw) => raw,
        }
    }
}

impl From<&str> for Status {
    fn from(raw: &str) -> Self {
        match raw {
            "Passive" => Self::Passive,
            "Active" | "" => Self::Active,
            "NeedsAttention" => Self::NeedsAttention,
            other => Self::Other(other.to_owned()),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Category {
    ApplicationStatus,
    Communications,
    SystemServices,
    Hardware,
    Other(String),
}

impl Category {
    pub fn as_str(&self) -> &str {
        match self {
            Self::ApplicationStatus => "ApplicationStatus",
            Self::Communications => "Communications",
            Self::SystemServices => "SystemServices",
            Self::Hardware => "Hardware",
            Self::Other(raw) => raw,
        }
    }
}

impl From<&str> for Category {
    fn from(raw: &str) -> Self {
        match raw {
            "ApplicationStatus" | "" => Self::ApplicationStatus,
            "Communications" => Self::Communications,
            "SystemServices" => Self::SystemServices,
            "Hardware" => Self::Hardware,
            other => Self::Other(other.to_owned()),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrayItem {
    pub address: ItemAddress,
    /// The unique name behind `address.service`, which is what a signal from this item
    /// carries in its header.
    pub owner: String,
    pub id: String,
    pub title: String,
    pub category: Category,
    pub status: Status,
    pub icon_name: String,
    pub icon_pixmap: Vec<Pixmap>,
    /// A directory of its own the application ships icons in, outside any theme.
    pub icon_theme_path: String,
    pub attention_icon_name: String,
    pub attention_icon_pixmap: Vec<Pixmap>,
    pub overlay_icon_name: String,
    pub overlay_icon_pixmap: Vec<Pixmap>,
    pub tooltip: Option<ToolTip>,
    /// The application asks that a left click open its menu rather than call `Activate`.
    /// Surfaced, not acted on: which button does what is the consumer's policy.
    pub item_is_menu: bool,
    pub menu: Option<String>,
    pub window_id: i32,
}

impl TrayItem {
    pub fn key(&self) -> String {
        self.address.key()
    }

    pub(crate) fn from_props(address: ItemAddress, owner: String, props: &Props) -> Self {
        let id = string(props, "Id");
        Self {
            // An item with no Id is still an item; the address is the only name it is
            // guaranteed to have and a consumer has to be able to key on something.
            title: {
                let title = string(props, "Title");
                if title.is_empty() {
                    id.clone()
                } else {
                    title
                }
            },
            id,
            category: Category::from(string(props, "Category").as_str()),
            status: Status::from(string(props, "Status").as_str()),
            icon_name: string(props, "IconName"),
            icon_pixmap: pixmaps(props, "IconPixmap"),
            icon_theme_path: string(props, "IconThemePath"),
            attention_icon_name: string(props, "AttentionIconName"),
            attention_icon_pixmap: pixmaps(props, "AttentionIconPixmap"),
            overlay_icon_name: string(props, "OverlayIconName"),
            overlay_icon_pixmap: pixmaps(props, "OverlayIconPixmap"),
            tooltip: tooltip(props, "ToolTip"),
            item_is_menu: boolean(props, "ItemIsMenu", false),
            menu: object_path(props, "Menu"),
            window_id: integer(props, "WindowId").unwrap_or(0),
            address,
            owner,
        }
    }
}

/// Unwraps a `v` box; returns the value itself otherwise.
fn unbox<'d, 'v>(value: &'d Value<'v>) -> &'d Value<'v> {
    match value {
        Value::Value(inner) => inner,
        other => other,
    }
}

fn prop<'p>(props: &'p Props, key: &str) -> Option<&'p Value<'p>> {
    props.get(key).map(|owned| unbox(owned))
}

fn string(props: &Props, key: &str) -> String {
    match prop(props, key) {
        Some(Value::Str(s)) => s.to_string(),
        Some(Value::ObjectPath(p)) => p.to_string(),
        _ => String::new(),
    }
}

fn object_path(props: &Props, key: &str) -> Option<String> {
    let path = match prop(props, key)? {
        Value::ObjectPath(p) => p.to_string(),
        Value::Str(s) => s.to_string(),
        _ => return None,
    };
    // Qt exports "/NO_DBUSMENU" when the item has no menu at all.
    (path.starts_with('/') && path != "/NO_DBUSMENU").then_some(path)
}

fn boolean(props: &Props, key: &str, default: bool) -> bool {
    match prop(props, key) {
        Some(&Value::Bool(b)) => b,
        _ => default,
    }
}

fn integer(props: &Props, key: &str) -> Option<i32> {
    match prop(props, key)? {
        Value::I32(i) => Some(*i),
        Value::U32(u) => Some(*u as i32),
        _ => None,
    }
}

fn pixmaps(props: &Props, key: &str) -> Vec<Pixmap> {
    match prop(props, key) {
        Some(Value::Array(array)) => pixmap_array(array),
        _ => Vec::new(),
    }
}

fn pixmap_array(array: &zvariant::Array<'_>) -> Vec<Pixmap> {
    array.iter().filter_map(pixmap).collect()
}

fn pixmap(value: &Value<'_>) -> Option<Pixmap> {
    let Value::Structure(fields) = unbox(value) else {
        return None;
    };
    let fields = fields.fields();
    let (&Value::I32(width), &Value::I32(height), Value::Array(bytes)) =
        (fields.first()?, fields.get(1)?, fields.get(2)?)
    else {
        return None;
    };
    let argb32: Vec<u8> = bytes
        .iter()
        .filter_map(|b| match b {
            &Value::U8(byte) => Some(byte),
            _ => None,
        })
        .collect();
    // A truncated pixmap is worse than none: a consumer that trusts the dimensions
    // would read past the end of it.
    let expected = (width as i64) * (height as i64) * 4;
    (width > 0 && height > 0 && argb32.len() as i64 == expected).then_some(Pixmap {
        width,
        height,
        argb32,
    })
}

fn tooltip(props: &Props, key: &str) -> Option<ToolTip> {
    let Value::Structure(fields) = prop(props, key)? else {
        return None;
    };
    let fields = fields.fields();
    let text = |index: usize| match fields.get(index) {
        Some(Value::Str(s)) => s.to_string(),
        _ => String::new(),
    };
    let tooltip = ToolTip {
        icon_name: text(0),
        icon_pixmap: match fields.get(1) {
            Some(Value::Array(array)) => pixmap_array(array),
            _ => Vec::new(),
        },
        title: text(2),
        description: text(3),
    };
    // Every item exports the property whether or not it has a tooltip; an empty one is
    // absence, and a consumer should fall back to the title rather than draw a blank.
    (tooltip != ToolTip::default()).then_some(tooltip)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_address_survives_both_forms_a_watcher_publishes() {
        let combined = ItemAddress::parse(":1.70/StatusNotifierItem").unwrap();
        assert_eq!(combined.service, ":1.70");
        assert_eq!(combined.path, "/StatusNotifierItem");
        assert_eq!(combined.key(), ":1.70/StatusNotifierItem");

        let bare = ItemAddress::parse("org.kde.StatusNotifierItem-1234-1").unwrap();
        assert_eq!(bare.service, "org.kde.StatusNotifierItem-1234-1");
        assert_eq!(bare.path, "/StatusNotifierItem");

        let nested = ItemAddress::parse(":1.9/org/ayatana/NotificationItem/nm_applet").unwrap();
        assert_eq!(nested.service, ":1.9");
        assert_eq!(nested.path, "/org/ayatana/NotificationItem/nm_applet");

        assert!(ItemAddress::parse("").is_none());
        assert!(ItemAddress::parse("/StatusNotifierItem").is_none());
    }

    #[test]
    fn a_registration_by_path_is_credited_to_the_sender_not_the_argument() {
        let by_path = ItemAddress::from_registration("/org/ayatana/NotificationItem/x", ":1.9");
        assert_eq!(by_path.unwrap().key(), ":1.9/org/ayatana/NotificationItem/x");

        let by_name = ItemAddress::from_registration("org.example.Item", ":1.9").unwrap();
        assert_eq!(by_name.service, "org.example.Item");
        assert_eq!(by_name.path, "/StatusNotifierItem");
    }

    fn props(pairs: Vec<(&str, Value<'static>)>) -> Props {
        pairs
            .into_iter()
            .map(|(k, v)| (k.to_owned(), OwnedValue::try_from(v).unwrap()))
            .collect()
    }

    fn pixmap_value(width: i32, height: i32, bytes: Vec<u8>) -> Value<'static> {
        Value::from(vec![Value::from(zvariant::Structure::from((
            width, height, bytes,
        )))])
    }

    #[test]
    fn icons_come_through_as_a_name_and_untouched_bytes() {
        let argb: Vec<u8> = (0..16u8).collect();
        let item = TrayItem::from_props(
            ItemAddress::parse(":1.70/StatusNotifierItem").unwrap(),
            ":1.70".into(),
            &props(vec![
                ("Id", "TelegramDesktop".into()),
                ("IconName", "telegram-symbolic".into()),
                ("IconPixmap", pixmap_value(2, 2, argb.clone())),
            ]),
        );

        assert_eq!(item.icon_name, "telegram-symbolic");
        assert_eq!(item.icon_pixmap.len(), 1);
        assert_eq!(item.icon_pixmap[0].width, 2);
        assert_eq!(item.icon_pixmap[0].argb32, argb);
        // No Title, so the id stands in rather than an empty label.
        assert_eq!(item.title, "TelegramDesktop");
    }

    #[test]
    fn a_pixmap_whose_bytes_do_not_match_its_dimensions_is_dropped() {
        let item = TrayItem::from_props(
            ItemAddress::parse(":1.70/StatusNotifierItem").unwrap(),
            ":1.70".into(),
            &props(vec![("IconPixmap", pixmap_value(24, 24, vec![0u8; 16]))]),
        );
        assert!(item.icon_pixmap.is_empty());
    }

    #[test]
    fn missing_and_mistyped_properties_fall_back_instead_of_failing() {
        let item = TrayItem::from_props(
            ItemAddress::parse(":1.70/StatusNotifierItem").unwrap(),
            ":1.70".into(),
            &props(vec![
                ("Title", 42i32.into()),
                ("ItemIsMenu", "yes".into()),
                ("Menu", "/NO_DBUSMENU".into()),
                ("Status", "".into()),
            ]),
        );

        assert_eq!(item.title, "");
        assert!(!item.item_is_menu);
        assert_eq!(item.menu, None);
        assert_eq!(item.status, Status::Active);
        assert_eq!(item.category, Category::ApplicationStatus);
        assert_eq!(item.tooltip, None);
    }

    #[test]
    fn an_empty_tooltip_reads_as_no_tooltip() {
        let empty = Value::from(zvariant::Structure::from((
            String::new(),
            Vec::<Value<'static>>::new(),
            String::new(),
            String::new(),
        )));
        let filled = Value::from(zvariant::Structure::from((
            String::new(),
            Vec::<Value<'static>>::new(),
            "Telegram Desktop".to_owned(),
            String::new(),
        )));

        let address = ItemAddress::parse(":1.70/StatusNotifierItem").unwrap();
        let none = TrayItem::from_props(
            address.clone(),
            ":1.70".into(),
            &props(vec![("ToolTip", empty)]),
        );
        let some = TrayItem::from_props(address, ":1.70".into(), &props(vec![("ToolTip", filled)]));

        assert_eq!(none.tooltip, None);
        assert_eq!(some.tooltip.unwrap().title, "Telegram Desktop");
    }
}
