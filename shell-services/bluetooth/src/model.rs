use crate::props::{self, Props};

/// BlueZ's `Adapter1.PowerState`, which `Powered` alone cannot stand in for: a
/// controller that refuses the mgmt command leaves `Powered = true` and this at `Off`,
/// and `OffBlocked` is the rfkill case arriving from the other direction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PowerState {
    On,
    Off,
    OffEnabling,
    OnDisabling,
    OffBlocked,
    Unknown,
}

impl PowerState {
    fn parse(value: Option<&str>) -> Self {
        match value {
            Some("on") => Self::On,
            Some("off") => Self::Off,
            Some("off-enabling") => Self::OffEnabling,
            Some("on-disabling") => Self::OnDisabling,
            Some("off-blocked") => Self::OffBlocked,
            _ => Self::Unknown,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Adapter {
    pub path: String,
    /// `hci0`, the name `rfkill list` and `bluetoothctl` print.
    pub id: String,
    pub address: String,
    pub name: String,
    pub alias: String,
    pub powered: bool,
    /// What the controller actually did with the last `Powered` write.
    pub power_state: PowerState,
    pub discoverable: bool,
    pub discovering: bool,
    pub pairable: bool,
}

impl Adapter {
    pub(crate) fn from_props(path: &str, props: &Props) -> Self {
        Self {
            path: path.to_owned(),
            id: last_segment(path).to_owned(),
            address: props::text(props, "Address").unwrap_or_default(),
            name: props::text(props, "Name").unwrap_or_default(),
            alias: props::text(props, "Alias").unwrap_or_default(),
            powered: props::boolean(props, "Powered").unwrap_or(false),
            power_state: PowerState::parse(props::text(props, "PowerState").as_deref()),
            discoverable: props::boolean(props, "Discoverable").unwrap_or(false),
            discovering: props::boolean(props, "Discovering").unwrap_or(false),
            pairable: props::boolean(props, "Pairable").unwrap_or(false),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Device {
    pub path: String,
    /// The adapter object path this device hangs off, so a consumer can group without
    /// re-reading `Device1.Adapter`.
    pub adapter: String,
    pub address: String,
    /// Absent where BlueZ never learned one. `Alias` always has a value, falling back to
    /// the address with dashes, which is what the QML's MAC test at
    /// `BluetoothStatus.qml:38` keys off.
    pub name: Option<String>,
    pub alias: String,
    pub paired: bool,
    pub trusted: bool,
    pub connected: bool,
    pub blocked: bool,
    pub icon: Option<String>,
    pub rssi: Option<i16>,
    /// `org.bluez.Battery1.Percentage`, only where the device publishes it.
    pub battery: Option<u8>,
}

impl Device {
    pub(crate) fn from_props(path: &str, props: &Props, battery: Option<&Props>) -> Self {
        Self {
            path: path.to_owned(),
            adapter: parent(path).to_owned(),
            address: props::text(props, "Address").unwrap_or_default(),
            name: props::text(props, "Name"),
            alias: props::text(props, "Alias").unwrap_or_default(),
            paired: props::boolean(props, "Paired").unwrap_or(false),
            trusted: props::boolean(props, "Trusted").unwrap_or(false),
            connected: props::boolean(props, "Connected").unwrap_or(false),
            blocked: props::boolean(props, "Blocked").unwrap_or(false),
            icon: props::text(props, "Icon"),
            rssi: props::i16_at(props, "RSSI"),
            battery: battery.and_then(|b| props::u8_at(b, "Percentage")),
        }
    }
}

fn last_segment(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

fn parent(path: &str) -> &str {
    match path.rfind('/') {
        Some(0) | None => "/",
        Some(index) => &path[..index],
    }
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

    /// The `GetManagedObjects` reply this seat actually returns for `/org/bluez/hci0`.
    #[test]
    fn the_adapter_reads_the_fields_bluetoothctl_show_prints() {
        let adapter = Adapter::from_props(
            "/org/bluez/hci0",
            &props(&[
                ("Address", "64:4A:7D:60:DE:1F".into()),
                ("Name", "koompi".into()),
                ("Alias", "koompi".into()),
                ("Powered", true.into()),
                ("PowerState", "on".into()),
                ("Discoverable", false.into()),
                ("Discovering", false.into()),
                ("Pairable", false.into()),
            ]),
        );

        assert_eq!(adapter.id, "hci0");
        assert_eq!(adapter.address, "64:4A:7D:60:DE:1F");
        assert_eq!(adapter.alias, "koompi");
        assert!(adapter.powered);
        assert_eq!(adapter.power_state, PowerState::On);
        assert!(!adapter.discovering);
    }

    /// A `Powered = true` the controller never carried out, which is the state this
    /// seat's wedged hci0 sits in. `Powered` alone reads as a working adapter.
    #[test]
    fn power_state_contradicts_powered_when_the_controller_refused_the_write() {
        let adapter = Adapter::from_props(
            "/org/bluez/hci0",
            &props(&[("Powered", true.into()), ("PowerState", "off".into())]),
        );

        assert!(adapter.powered);
        assert_eq!(adapter.power_state, PowerState::Off);
    }

    /// The rfkill soft block seen from BlueZ's side.
    #[test]
    fn a_blocked_radio_reads_as_off_blocked() {
        let adapter = Adapter::from_props(
            "/org/bluez/hci0",
            &props(&[("PowerState", "off-blocked".into())]),
        );

        assert_eq!(adapter.power_state, PowerState::OffBlocked);
        assert_eq!(
            Adapter::from_props("/org/bluez/hci0", &props(&[])).power_state,
            PowerState::Unknown
        );
    }

    #[test]
    fn a_device_takes_its_adapter_from_its_object_path_and_its_battery_from_the_other_interface() {
        let device = Device::from_props(
            "/org/bluez/hci0/dev_AC_80_0A_11_22_33",
            &props(&[
                ("Address", "AC:80:0A:11:22:33".into()),
                ("Alias", "WH-1000XM4".into()),
                ("Name", "WH-1000XM4".into()),
                ("Paired", true.into()),
                ("Connected", true.into()),
                ("Icon", "audio-headset".into()),
                ("RSSI", (-54i16).into()),
            ]),
            Some(&props(&[("Percentage", 80u8.into())])),
        );

        assert_eq!(device.adapter, "/org/bluez/hci0");
        assert_eq!(device.name.as_deref(), Some("WH-1000XM4"));
        assert_eq!(device.rssi, Some(-54));
        assert_eq!(device.battery, Some(80));
        assert!(!device.trusted);
    }

    /// A device BlueZ never learned a name for publishes no `Name` at all; `Alias` is
    /// the dashed address, and the absent `Name` is what tells a consumer that.
    #[test]
    fn a_nameless_device_reports_no_name_rather_than_the_address() {
        let device = Device::from_props(
            "/org/bluez/hci0/dev_11_22_33_44_55_66",
            &props(&[
                ("Address", "11:22:33:44:55:66".into()),
                ("Alias", "11-22-33-44-55-66".into()),
            ]),
            None,
        );

        assert_eq!(device.name, None);
        assert_eq!(device.alias, "11-22-33-44-55-66");
        assert_eq!(device.battery, None);
    }
}
