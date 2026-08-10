use std::collections::HashMap;

use zvariant::OwnedValue;

pub type Props = HashMap<String, OwnedValue>;

pub fn boolean(props: &Props, key: &str) -> Option<bool> {
    props.get(key)?.downcast_ref::<bool>().ok()
}

pub fn text(props: &Props, key: &str) -> Option<String> {
    props.get(key)?.downcast_ref::<String>().ok()
}

pub fn i16_at(props: &Props, key: &str) -> Option<i16> {
    props.get(key)?.downcast_ref::<i16>().ok()
}

pub fn u8_at(props: &Props, key: &str) -> Option<u8> {
    props.get(key)?.downcast_ref::<u8>().ok()
}
