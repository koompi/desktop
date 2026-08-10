//! `a{sv}` in, decided data out.
//!
//! This is where applications diverge most. The spec names a type for each hint and almost
//! nobody sends exactly that type: `urgency` is a byte in the spec and arrives as a `u32`
//! from half the senders, `transient` is a boolean and arrives as a `1`. So every read here
//! is by shape rather than by declared type.
//!
//! One rule decides every failure case: **a malformed hint drops that hint, never the
//! notification.** A picture that cannot be trusted is worth less than the message it came
//! attached to.

use std::collections::{BTreeMap, HashMap};

use zvariant::{OwnedValue, Value};

use crate::model::{Icon, ImageData, Urgency};

pub type Raw = HashMap<String, OwnedValue>;

/// Newest spelling first: 1.2 renamed `image_data` to `image-data`, and `icon_data` is the
/// 1.0 name that Pidgin and its descendants still send.
const IMAGE_DATA_KEYS: [&str; 3] = ["image-data", "image_data", "icon_data"];
const IMAGE_PATH_KEYS: [&str; 2] = ["image-path", "image_path"];

const DECODED_KEYS: [&str; 11] = [
    "urgency",
    "image-data",
    "image_data",
    "icon_data",
    "image-path",
    "image_path",
    "desktop-entry",
    "transient",
    "resident",
    "category",
    "value",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Hints {
    pub urgency: Urgency,
    /// Inline pixels, forwarded untouched. Outranks [`Hints::image_path`] per the spec.
    pub image: Option<ImageData>,
    pub image_path: Option<Icon>,
    /// The sender's `.desktop` file, minus the suffix. The only reliable way to tie a
    /// notification back to an installed application, since `app_name` is free text.
    pub desktop_entry: Option<String>,
    pub category: Option<String>,
    /// Do not keep this one in history once its popup is gone.
    pub transient: bool,
    /// Invoking an action leaves this one on screen instead of closing it.
    pub resident: bool,
    /// 0-100 progress, as senders like the volume OSD use it.
    pub value: Option<i32>,
    /// Every hint we did not decode, rendered rather than interpreted, so a sender doing
    /// something the spec never described can be seen instead of silently dropped.
    pub other: BTreeMap<String, String>,
}

impl Default for Hints {
    fn default() -> Self {
        Self {
            urgency: Urgency::Normal,
            image: None,
            image_path: None,
            desktop_entry: None,
            category: None,
            transient: false,
            resident: false,
            value: None,
            other: BTreeMap::new(),
        }
    }
}

impl Hints {
    pub fn decode(raw: &Raw) -> Self {
        Self {
            urgency: integer(raw, "urgency")
                .map(|level| Urgency::from(level.clamp(0, 255) as u8))
                .unwrap_or(Urgency::Normal),
            image: IMAGE_DATA_KEYS
                .iter()
                .find_map(|key| image_data(raw, key))
                .and_then(ImageData::validate),
            image_path: IMAGE_PATH_KEYS
                .iter()
                .find_map(|key| text(raw, key))
                .map(|path| Icon::parse(&path))
                .filter(|icon| *icon != Icon::Empty),
            desktop_entry: text(raw, "desktop-entry").filter(|entry| !entry.is_empty()),
            category: text(raw, "category").filter(|category| !category.is_empty()),
            transient: flag(raw, "transient"),
            resident: flag(raw, "resident"),
            value: integer(raw, "value"),
            other: raw
                .iter()
                .filter(|(key, _)| !DECODED_KEYS.contains(&key.as_str()))
                .map(|(key, value)| (key.clone(), format!("{:?}", unbox(value))))
                .collect(),
        }
    }
}

/// A hint arrives inside a variant, and some senders nest a second one.
fn unbox<'d, 'v>(value: &'d Value<'v>) -> &'d Value<'v> {
    match value {
        Value::Value(inner) => unbox(inner),
        other => other,
    }
}

fn hint<'r>(raw: &'r Raw, key: &str) -> Option<&'r Value<'r>> {
    raw.get(key).map(|owned| unbox(owned))
}

fn text(raw: &Raw, key: &str) -> Option<String> {
    match hint(raw, key)? {
        Value::Str(text) => Some(text.to_string()),
        _ => None,
    }
}

/// Every width in the wild: the spec's type, and the four others senders reach for.
fn integer(raw: &Raw, key: &str) -> Option<i32> {
    match hint(raw, key)? {
        Value::U8(byte) => Some(i32::from(*byte)),
        Value::I16(small) => Some(i32::from(*small)),
        Value::U16(small) => Some(i32::from(*small)),
        Value::I32(value) => Some(*value),
        Value::U32(value) => i32::try_from(*value).ok(),
        Value::I64(value) => i32::try_from(*value).ok(),
        Value::U64(value) => i32::try_from(*value).ok(),
        _ => None,
    }
}

/// A boolean hint sent as a number is still a boolean hint.
fn flag(raw: &Raw, key: &str) -> bool {
    match hint(raw, key) {
        Some(Value::Bool(set)) => *set,
        _ => integer(raw, key).is_some_and(|value| value != 0),
    }
}

fn image_data(raw: &Raw, key: &str) -> Option<ImageData> {
    let Value::Structure(fields) = hint(raw, key)? else {
        return None;
    };
    let fields = fields.fields();
    let number = |index: usize| match unbox(fields.get(index)?) {
        Value::I32(value) => Some(*value),
        Value::U32(value) => i32::try_from(*value).ok(),
        _ => None,
    };

    let has_alpha = match unbox(fields.get(3)?) {
        Value::Bool(set) => *set,
        Value::I32(value) => *value != 0,
        _ => return None,
    };

    Some(ImageData {
        width: number(0)?,
        height: number(1)?,
        rowstride: number(2)?,
        has_alpha,
        bits_per_sample: number(4)?,
        channels: number(5)?,
        bytes: bytes(unbox(fields.get(6)?))?,
    })
}

/// `ay` arrives either as a byte array or, from a few senders, as an array of variants.
fn bytes(value: &Value<'_>) -> Option<Vec<u8>> {
    let Value::Array(array) = value else {
        return None;
    };
    array
        .iter()
        .map(|element| match unbox(element) {
            Value::U8(byte) => Some(*byte),
            _ => None,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use zvariant::Structure;

    fn raw(pairs: Vec<(&str, Value<'static>)>) -> Raw {
        pairs
            .into_iter()
            .map(|(key, value)| (key.to_owned(), OwnedValue::try_from(value).unwrap()))
            .collect()
    }

    /// Byte for byte what `notify-send -i <png>` puts on the wire for a 2x2 RGBA icon, with
    /// the padded stride a real GdkPixbuf hands over.
    fn captured_icon() -> Value<'static> {
        let pixels: Vec<u8> = vec![
            0xff, 0x00, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0xde, 0xad, // row 0 + padding
            0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x00, 0x80, // row 1, unpadded tail
        ];
        Value::from(Structure::from((
            2i32, 2i32, 10i32, true, 8i32, 4i32, pixels,
        )))
    }

    #[test]
    fn captured_image_bytes_survive_the_decode_unchanged() {
        let hints = Hints::decode(&raw(vec![("image-data", captured_icon())]));
        let image = hints.image.expect("real image-data was dropped");

        assert_eq!((image.width, image.height), (2, 2));
        assert_eq!(image.rowstride, 10);
        assert!(image.has_alpha);
        assert_eq!(image.bits_per_sample, 8);
        assert_eq!(image.channels, 4);
        assert_eq!(image.bytes.len(), 18);
        assert_eq!(
            image.bytes,
            [
                0xff, 0x00, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0xde, 0xad, 0x00, 0x00, 0xff, 0xff,
                0xff, 0xff, 0x00, 0x80
            ],
            "bytes were decoded, rescaled or reordered"
        );
    }

    #[test]
    fn the_older_spellings_are_read_and_the_newest_one_wins() {
        let old = Hints::decode(&raw(vec![("icon_data", captured_icon())]));
        assert!(
            old.image.is_some(),
            "icon_data from a 1.0 sender was ignored"
        );

        let both = Hints::decode(&raw(vec![
            ("icon_data", Value::from(Structure::from((1i32, 1i32)))),
            ("image-data", captured_icon()),
        ]));
        assert_eq!(both.image.unwrap().width, 2);
    }

    #[test]
    fn a_malformed_image_drops_the_hint_and_keeps_the_rest() {
        let hints = Hints::decode(&raw(vec![
            // Truncated: the geometry claims 64x64 and there are four bytes.
            (
                "image-data",
                Value::from(Structure::from((
                    64i32,
                    64i32,
                    256i32,
                    true,
                    8i32,
                    4i32,
                    vec![0u8; 4],
                ))),
            ),
            ("urgency", Value::U8(2)),
        ]));

        assert!(hints.image.is_none());
        assert_eq!(hints.urgency, Urgency::Critical);
    }

    #[test]
    fn urgency_and_the_boolean_hints_read_whatever_width_the_sender_chose() {
        assert_eq!(
            Hints::decode(&raw(vec![("urgency", Value::U8(2))])).urgency,
            Urgency::Critical
        );
        assert_eq!(
            Hints::decode(&raw(vec![("urgency", Value::U32(0))])).urgency,
            Urgency::Low
        );
        // Out of range and mistyped both fall back rather than fail.
        assert_eq!(
            Hints::decode(&raw(vec![("urgency", Value::I32(99))])).urgency,
            Urgency::Normal
        );
        assert_eq!(
            Hints::decode(&raw(vec![("urgency", Value::from("critical"))])).urgency,
            Urgency::Normal
        );

        assert!(Hints::decode(&raw(vec![("transient", Value::Bool(true))])).transient);
        assert!(Hints::decode(&raw(vec![("transient", Value::U32(1))])).transient);
        assert!(!Hints::decode(&raw(vec![("transient", Value::U32(0))])).transient);
        assert!(!Hints::decode(&raw(vec![])).transient);
    }

    #[test]
    fn the_string_hints_decode_and_an_empty_one_is_absence() {
        let hints = Hints::decode(&raw(vec![
            ("image-path", Value::from("file:///tmp/a%20b.png")),
            ("desktop-entry", Value::from("org.telegram.desktop")),
            ("category", Value::from("im.received")),
            ("value", Value::I32(42)),
        ]));

        assert_eq!(hints.image_path, Some(Icon::Path("/tmp/a b.png".into())));
        assert_eq!(hints.desktop_entry.as_deref(), Some("org.telegram.desktop"));
        assert_eq!(hints.category.as_deref(), Some("im.received"));
        assert_eq!(hints.value, Some(42));

        let empty = Hints::decode(&raw(vec![
            ("image-path", Value::from("")),
            ("desktop-entry", Value::from("")),
        ]));
        assert_eq!(empty.image_path, None);
        assert_eq!(empty.desktop_entry, None);
    }

    #[test]
    fn a_hint_nobody_documented_is_kept_where_it_can_be_seen() {
        let hints = Hints::decode(&raw(vec![
            ("x-kde-reply-placeholder-text", Value::from("Reply")),
            ("urgency", Value::U8(1)),
        ]));

        assert_eq!(hints.other.len(), 1, "a decoded hint leaked into `other`");
        assert!(hints.other["x-kde-reply-placeholder-text"].contains("Reply"));
    }
}
