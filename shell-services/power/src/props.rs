use std::collections::HashMap;

use zvariant::OwnedValue;

pub type Props = HashMap<String, OwnedValue>;

pub fn boolean(props: &Props, key: &str) -> Option<bool> {
    props.get(key)?.downcast_ref::<bool>().ok()
}

pub fn u32_at(props: &Props, key: &str) -> Option<u32> {
    props.get(key)?.downcast_ref::<u32>().ok()
}

pub fn i64_at(props: &Props, key: &str) -> Option<i64> {
    props.get(key)?.downcast_ref::<i64>().ok()
}

pub fn i32_at(props: &Props, key: &str) -> Option<i32> {
    props.get(key)?.downcast_ref::<i32>().ok()
}

pub fn f64_at(props: &Props, key: &str) -> Option<f64> {
    props.get(key)?.downcast_ref::<f64>().ok()
}

pub fn text(props: &Props, key: &str) -> Option<String> {
    props.get(key)?.downcast_ref::<String>().ok()
}
