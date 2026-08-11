//! Typed reads out of a `Properties.GetAll` reply.
//!
//! One round trip per object rather than one per property, so a view can never be
//! half of one sample and half of the next.

use std::collections::HashMap;

use zvariant::{OwnedValue, Value};

pub type Props = HashMap<String, OwnedValue>;

pub fn string(props: &Props, key: &str) -> Option<String> {
    match &**props.get(key)? {
        Value::Str(text) => Some(text.to_string()),
        _ => None,
    }
}

pub fn boolean(props: &Props, key: &str) -> Option<bool> {
    match &**props.get(key)? {
        Value::Bool(flag) => Some(*flag),
        _ => None,
    }
}

pub fn uint32(props: &Props, key: &str) -> Option<u32> {
    match &**props.get(key)? {
        Value::U32(number) => Some(*number),
        _ => None,
    }
}

/// logind spells a reference to another object as `(so)`: the id a human reads and the
/// path a caller uses. An empty id means no such reference, which is how a session
/// with no seat answers.
pub fn reference(props: &Props, key: &str) -> Option<(String, String)> {
    pair(props.get(key)?)
}

/// The same shape as an array, which is how a seat lists its sessions.
pub fn references(props: &Props, key: &str) -> Vec<(String, String)> {
    let Some(value) = props.get(key) else {
        return Vec::new();
    };
    let Value::Array(array) = unvariant(value) else {
        return Vec::new();
    };
    array.iter().filter_map(pair).collect()
}

/// A `v` that holds a `v`. GetAll unwraps one level; an array of variants keeps one.
fn unvariant<'v>(value: &'v Value<'v>) -> &'v Value<'v> {
    match value {
        Value::Value(inner) => inner.as_ref(),
        other => other,
    }
}

fn pair(value: &Value<'_>) -> Option<(String, String)> {
    let Value::Structure(fields) = unvariant(value) else {
        return None;
    };
    let [Value::Str(id), Value::ObjectPath(path)] = fields.fields() else {
        return None;
    };
    if id.is_empty() {
        return None;
    }
    Some((id.to_string(), path.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn props(entries: Vec<(&str, Value<'static>)>) -> Props {
        entries
            .into_iter()
            .map(|(key, value)| (key.to_owned(), OwnedValue::try_from(value).unwrap()))
            .collect()
    }

    #[test]
    fn a_missing_or_wrongly_typed_property_reads_as_absent_rather_than_panicking() {
        let props = props(vec![
            ("Id", Value::from("2")),
            ("Active", Value::from(true)),
        ]);
        assert_eq!(string(&props, "Id").as_deref(), Some("2"));
        assert_eq!(boolean(&props, "Active"), Some(true));
        assert_eq!(string(&props, "Active"), None);
        assert_eq!(boolean(&props, "Id"), None);
        assert_eq!(uint32(&props, "Leader"), None);
        assert_eq!(reference(&props, "Seat"), None);
    }

    /// The `Seat` property as this session actually answers it.
    #[test]
    fn a_seat_reference_decodes_to_its_id_and_its_object_path() {
        let seat = Value::from(zvariant::Structure::from((
            "seat0",
            zvariant::ObjectPath::try_from("/org/freedesktop/login1/seat/seat0").unwrap(),
        )));
        let props = props(vec![("Seat", seat)]);
        assert_eq!(
            reference(&props, "Seat"),
            Some((
                "seat0".to_owned(),
                "/org/freedesktop/login1/seat/seat0".to_owned()
            ))
        );
    }

    /// A session with no seat answers `("", "/")`, which is not a seat.
    #[test]
    fn the_empty_seat_reference_a_manager_session_answers_with_is_no_seat() {
        let empty = Value::from(zvariant::Structure::from((
            "",
            zvariant::ObjectPath::try_from("/").unwrap(),
        )));
        let props = props(vec![("Seat", empty)]);
        assert_eq!(reference(&props, "Seat"), None);
    }

    #[test]
    fn a_seats_session_list_decodes_every_row() {
        let row = |id: &str, path: &'static str| {
            Value::from(zvariant::Structure::from((
                id.to_owned(),
                zvariant::ObjectPath::try_from(path).unwrap(),
            )))
        };
        let array = zvariant::Array::from(vec![
            row("2", "/org/freedesktop/login1/session/_32"),
            row("5", "/org/freedesktop/login1/session/_35"),
        ]);
        let props = props(vec![("Sessions", Value::from(array))]);
        let sessions = references(&props, "Sessions");
        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].0, "2");
        assert_eq!(sessions[1].1, "/org/freedesktop/login1/session/_35");
        assert!(references(&props, "Nothing").is_empty());
    }
}
