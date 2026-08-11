use std::collections::HashMap;

use zvariant::{OwnedValue, Value};

pub type Props = HashMap<String, OwnedValue>;

pub fn boolean(props: &Props, key: &str) -> Option<bool> {
    props.get(key)?.downcast_ref::<bool>().ok()
}

pub fn u32_at(props: &Props, key: &str) -> Option<u32> {
    props.get(key)?.downcast_ref::<u32>().ok()
}

pub fn u8_at(props: &Props, key: &str) -> Option<u8> {
    props.get(key)?.downcast_ref::<u8>().ok()
}

pub fn i64_at(props: &Props, key: &str) -> Option<i64> {
    props.get(key)?.downcast_ref::<i64>().ok()
}

pub fn i32_at(props: &Props, key: &str) -> Option<i32> {
    props.get(key)?.downcast_ref::<i32>().ok()
}

pub fn text(props: &Props, key: &str) -> Option<String> {
    props.get(key)?.downcast_ref::<String>().ok()
}

pub fn path(props: &Props, key: &str) -> Option<String> {
    props
        .get(key)?
        .downcast_ref::<zvariant::ObjectPath<'_>>()
        .ok()
        .map(|p| p.as_str().to_owned())
}

pub fn paths(props: &Props, key: &str) -> Option<Vec<String>> {
    let Value::Array(array) = &**props.get(key)? else {
        return None;
    };
    array
        .iter()
        .map(|value| match value {
            Value::ObjectPath(p) => Some(p.as_str().to_owned()),
            _ => None,
        })
        .collect()
}

/// `Ssid` is `ay`, not `s`. Anything that reads it as a string has already lost the
/// bytes an access point is free to broadcast.
pub fn bytes(props: &Props, key: &str) -> Option<Vec<u8>> {
    let Value::Array(array) = &**props.get(key)? else {
        return None;
    };
    array
        .iter()
        .map(|value| match value {
            Value::U8(byte) => Some(*byte),
            _ => None,
        })
        .collect()
}
