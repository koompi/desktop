//! The `GetManagedObjects` tree, kept current from the signals rather than re-read.
//!
//! BlueZ emits `PropertiesChanged` per device per advertisement while discovery runs, so
//! a round trip per signal would be a round trip per beacon.

use std::collections::HashMap;

use crate::model::{Adapter, Device};
use crate::props::Props;

pub const ADAPTER_IFACE: &str = "org.bluez.Adapter1";
pub const DEVICE_IFACE: &str = "org.bluez.Device1";
pub const BATTERY_IFACE: &str = "org.bluez.Battery1";

#[derive(Debug, Default)]
pub struct Objects {
    tree: HashMap<String, HashMap<String, Props>>,
}

impl Objects {
    pub fn add(&mut self, path: &str, interfaces: HashMap<String, Props>) -> bool {
        let tracked = interfaces.keys().any(|iface| is_tracked(iface));
        self.tree
            .entry(path.to_owned())
            .or_default()
            .extend(interfaces);
        tracked
    }

    pub fn remove(&mut self, path: &str, interfaces: &[String]) -> bool {
        let Some(object) = self.tree.get_mut(path) else {
            return false;
        };
        let tracked = interfaces.iter().any(|iface| is_tracked(iface));
        for interface in interfaces {
            object.remove(interface);
        }
        if object.is_empty() {
            self.tree.remove(path);
        }
        tracked
    }

    pub fn merge(
        &mut self,
        path: &str,
        interface: &str,
        changed: Props,
        invalidated: &[String],
    ) -> bool {
        if !is_tracked(interface) {
            return false;
        }
        let Some(props) = self.tree.get_mut(path).and_then(|o| o.get_mut(interface)) else {
            return false;
        };
        for key in invalidated {
            props.remove(key);
        }
        props.extend(changed);
        true
    }

    /// Sorted by object path so an unchanged bus produces an unchanged state and the
    /// watch channel stays quiet. Presentation order is the consumer's, per the QML
    /// comparator this crate deliberately does not carry.
    pub fn adapters(&self) -> Vec<Adapter> {
        let mut adapters: Vec<Adapter> = self
            .tree
            .iter()
            .filter_map(|(path, object)| {
                object
                    .get(ADAPTER_IFACE)
                    .map(|props| Adapter::from_props(path, props))
            })
            .collect();
        adapters.sort_by(|a, b| a.path.cmp(&b.path));
        adapters
    }

    pub fn devices(&self) -> Vec<Device> {
        let mut devices: Vec<Device> = self
            .tree
            .iter()
            .filter_map(|(path, object)| {
                object
                    .get(DEVICE_IFACE)
                    .map(|props| Device::from_props(path, props, object.get(BATTERY_IFACE)))
            })
            .collect();
        devices.sort_by(|a, b| a.path.cmp(&b.path));
        devices
    }
}

fn is_tracked(interface: &str) -> bool {
    matches!(interface, ADAPTER_IFACE | DEVICE_IFACE | BATTERY_IFACE)
}

#[cfg(test)]
mod tests {
    use super::*;
    use zvariant::{OwnedValue, Value};

    fn props(pairs: &[(&str, Value<'static>)]) -> Props {
        pairs
            .iter()
            .map(|(key, value)| {
                (
                    (*key).to_owned(),
                    OwnedValue::try_from(value.clone()).unwrap(),
                )
            })
            .collect()
    }

    fn seat() -> Objects {
        let mut objects = Objects::default();
        objects.add(
            "/org/bluez/hci0",
            HashMap::from([(
                ADAPTER_IFACE.to_owned(),
                props(&[
                    ("Address", "64:4A:7D:60:DE:1F".into()),
                    ("Alias", "koompi".into()),
                    ("Powered", true.into()),
                ]),
            )]),
        );
        objects
    }

    #[test]
    fn a_device_added_after_the_initial_read_shows_up_without_another_round_trip() {
        let mut objects = seat();
        assert!(objects.devices().is_empty());

        let tracked = objects.add(
            "/org/bluez/hci0/dev_AC_80_0A_11_22_33",
            HashMap::from([(
                DEVICE_IFACE.to_owned(),
                props(&[
                    ("Address", "AC:80:0A:11:22:33".into()),
                    ("Alias", "WH-1000XM4".into()),
                    ("Connected", false.into()),
                ]),
            )]),
        );

        assert!(tracked);
        assert_eq!(objects.devices().len(), 1);
        assert_eq!(objects.devices()[0].adapter, "/org/bluez/hci0");
    }

    #[test]
    fn a_properties_changed_edits_the_object_in_place() {
        let mut objects = seat();

        assert!(objects.merge(
            "/org/bluez/hci0",
            ADAPTER_IFACE,
            props(&[("Powered", false.into()), ("Discovering", true.into())]),
            &[],
        ));

        let adapter = &objects.adapters()[0];
        assert!(!adapter.powered);
        assert!(adapter.discovering);
        assert_eq!(adapter.alias, "koompi");
    }

    /// BlueZ drops `RSSI` by invalidating it when a device stops advertising, and a
    /// stale signal strength on a device that is gone is worse than none.
    #[test]
    fn an_invalidated_property_is_dropped_not_kept() {
        let mut objects = seat();
        objects.add(
            "/org/bluez/hci0/dev_11_22_33_44_55_66",
            HashMap::from([(
                DEVICE_IFACE.to_owned(),
                props(&[
                    ("Address", "11:22:33:44:55:66".into()),
                    ("RSSI", (-70i16).into()),
                ]),
            )]),
        );
        assert_eq!(objects.devices()[0].rssi, Some(-70));

        objects.merge(
            "/org/bluez/hci0/dev_11_22_33_44_55_66",
            DEVICE_IFACE,
            Props::new(),
            &["RSSI".to_owned()],
        );

        assert_eq!(objects.devices()[0].rssi, None);
    }

    #[test]
    fn the_battery_interface_arriving_late_lands_on_the_device_that_already_exists() {
        let mut objects = seat();
        objects.add(
            "/org/bluez/hci0/dev_AC_80_0A_11_22_33",
            HashMap::from([(DEVICE_IFACE.to_owned(), props(&[("Paired", true.into())]))]),
        );
        assert_eq!(objects.devices()[0].battery, None);

        objects.add(
            "/org/bluez/hci0/dev_AC_80_0A_11_22_33",
            HashMap::from([(
                BATTERY_IFACE.to_owned(),
                props(&[("Percentage", 65u8.into())]),
            )]),
        );

        assert_eq!(objects.devices()[0].battery, Some(65));
    }

    #[test]
    fn removing_the_device_interface_removes_the_device() {
        let mut objects = seat();
        objects.add(
            "/org/bluez/hci0/dev_AC_80_0A_11_22_33",
            HashMap::from([(DEVICE_IFACE.to_owned(), props(&[("Paired", true.into())]))]),
        );

        assert!(objects.remove(
            "/org/bluez/hci0/dev_AC_80_0A_11_22_33",
            &[DEVICE_IFACE.to_owned()],
        ));

        assert!(objects.devices().is_empty());
        assert_eq!(objects.adapters().len(), 1);
    }

    /// `/org/bluez` itself carries `AgentManager1` and `ProfileManager1`, and BlueZ
    /// chatters on interfaces this crate models none of.
    #[test]
    fn an_interface_this_crate_does_not_model_is_not_a_reason_to_republish() {
        let mut objects = seat();

        let tracked = objects.add(
            "/org/bluez",
            HashMap::from([("org.bluez.AgentManager1".to_owned(), Props::new())]),
        );

        assert!(!tracked);
        assert!(!objects.merge("/org/bluez/hci0", "org.bluez.Media1", Props::new(), &[]));
    }
}
