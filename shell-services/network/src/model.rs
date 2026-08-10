//! The state `Network.qml:17-38` publishes, with the derivations it does in JavaScript
//! done here instead, so a consumer can be diffed against the QML property for property.

use koompi_service::PollRate;

use crate::ap::{strongest_per_ssid, AccessPoint, Ssid};
use crate::enums::{ActiveState, Connectivity, DeviceState, DeviceType, NmState, WifiStatus};
use crate::props::{self, Props};

#[derive(Debug, Clone, PartialEq)]
pub struct Device {
    pub path: String,
    pub interface: String,
    pub kind: DeviceType,
    pub state: DeviceState,
    pub managed: bool,
}

impl Device {
    pub fn from_props(path: &str, props: &Props) -> Self {
        Self {
            path: path.to_owned(),
            interface: props::text(props, "Interface").unwrap_or_default(),
            kind: DeviceType::from_u32(props::u32_at(props, "DeviceType").unwrap_or(0)),
            state: DeviceState::from_u32(props::u32_at(props, "State").unwrap_or(0)),
            managed: props::boolean(props, "Managed").unwrap_or(false),
        }
    }
}

/// `Device.Wired`. `Network.qml:198` infers ethernet from the word `connected` next to
/// the word `ethernet` in nmcli's device table and never sees carrier at all.
#[derive(Debug, Clone, PartialEq)]
pub struct WiredDevice {
    pub device: Device,
    /// A cable in the socket. False with `state == Activated` cannot happen; true with
    /// `state == Disconnected` is an unplugged-then-replugged link NM has not brought up.
    pub carrier: bool,
    /// Mbit/s, 0 when the link is down.
    pub speed: u32,
    pub hw_address: String,
}

impl WiredDevice {
    pub fn connected(&self) -> bool {
        self.device.state == DeviceState::Activated
    }
}

/// `Device.Wireless` plus everything `Network.qml` derives about wifi.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct WifiState {
    /// `Network.qml:17`, but honestly: a wireless radio exists on this seat.
    pub present: bool,
    /// The manager's `WirelessEnabled`, `Network.qml:259`.
    pub enabled: bool,
    pub status: WifiStatus,
    /// `Network.qml:21`. A scan this crate asked for that has not landed yet.
    pub scanning: bool,
    /// `Network.qml:22`.
    pub connecting: bool,
    /// `Network.qml:23`, the SSID being brought up.
    pub connect_target: Option<Ssid>,
    pub interface: String,
    pub hw_address: String,
    pub device_path: String,
    pub device_state: DeviceState,
    /// Current link rate in kbit/s, 0 when not associated.
    pub bitrate: u32,
    /// `CLOCK_BOOTTIME` milliseconds of the last completed scan, -1 if never scanned.
    pub last_scan: i64,
    /// Every access point in range, one entry per BSSID, exactly the rows
    /// `nmcli -g ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY d w` prints.
    pub networks: Vec<AccessPoint>,
    /// `Device.Wireless.ActiveAccessPoint`. Held as the path, because the AP list and
    /// the device's own properties refresh on different signals and whichever lands
    /// second has to be able to find the other.
    pub active_ap_path: String,
    /// `Network.qml:25`, the associated access point.
    pub active: Option<AccessPoint>,
}

impl WifiState {
    /// `Network.qml:24` after the dedupe at `:290-308`: one row per SSID.
    pub fn networks_by_ssid(&self) -> Vec<AccessPoint> {
        strongest_per_ssid(&self.networks)
    }
}

/// `Connection.Active`, the object `nmcli -t -f NAME c show --active` prints the `Id` of.
#[derive(Debug, Clone, PartialEq)]
pub struct ActiveConnection {
    pub path: String,
    pub id: String,
    pub uuid: String,
    /// `802-11-wireless`, `802-3-ethernet`, `bridge`, and so on.
    pub kind: String,
    pub state: ActiveState,
    pub default_route: bool,
    pub vpn: bool,
    /// The `Settings.Connection` this was activated from, the object a PSK change
    /// would have to `Update`.
    pub settings_path: String,
    pub devices: Vec<String>,
}

impl ActiveConnection {
    pub fn from_props(path: &str, props: &Props) -> Self {
        Self {
            path: path.to_owned(),
            id: props::text(props, "Id").unwrap_or_default(),
            uuid: props::text(props, "Uuid").unwrap_or_default(),
            kind: props::text(props, "Type").unwrap_or_default(),
            state: ActiveState::from_u32(props::u32_at(props, "State").unwrap_or(0)),
            default_route: props::boolean(props, "Default").unwrap_or(false),
            vpn: props::boolean(props, "Vpn").unwrap_or(false),
            settings_path: props::path(props, "Connection").unwrap_or_default(),
            devices: props::paths(props, "Devices").unwrap_or_default(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct NetworkState {
    /// NetworkManager answered. False is `Error::Unavailable` territory, not a fault.
    pub available: bool,
    pub version: String,
    pub state: NmState,
    /// D09 item 7. `Portal` is the answer `Network.qml` opens a browser to guess at.
    pub connectivity: Connectivity,
    pub wifi: WifiState,
    pub wired: Vec<WiredDevice>,
    /// `PrimaryConnection`: the one carrying the default route.
    pub primary: Option<ActiveConnection>,
    pub active_connections: Vec<ActiveConnection>,
    pub poll_rate: PollRate,
}

impl NetworkState {
    /// `Network.qml:18`. Any wired device that is up.
    pub fn ethernet(&self) -> bool {
        self.wired.iter().any(WiredDevice::connected)
    }

    /// `Network.qml:37`.
    pub fn connected(&self) -> bool {
        self.ethernet() || (self.wifi.enabled && self.wifi.status == WifiStatus::Connected)
    }

    /// `Network.qml:35`, which takes the first row of `nmcli c show --active` and hopes
    /// it is the one the default route is on. `PrimaryConnection` says so outright.
    pub fn network_name(&self) -> &str {
        match &self.primary {
            Some(primary) => &primary.id,
            None => self
                .active_connections
                .first()
                .map(|c| c.id.as_str())
                .unwrap_or(""),
        }
    }

    /// `Network.qml:36`, the `awk '/^\*/{print $2}'` pipeline at `:241`.
    pub fn network_strength(&self) -> u8 {
        self.wifi.active.as_ref().map_or(0, |ap| ap.strength)
    }

    /// D09 item 7: associated, addressed, and still behind a login page.
    pub fn captive_portal(&self) -> bool {
        self.connectivity == Connectivity::Portal
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ap::Security;

    fn wired(state: DeviceState, carrier: bool) -> WiredDevice {
        WiredDevice {
            device: Device {
                path: "/org/freedesktop/NetworkManager/Devices/1".into(),
                interface: "enp0s31f6".into(),
                kind: DeviceType::Ethernet,
                state,
                managed: true,
            },
            carrier,
            speed: if carrier { 1000 } else { 0 },
            hw_address: "00:11:22:33:44:55".into(),
        }
    }

    fn associated(strength: u8) -> AccessPoint {
        AccessPoint {
            path: "/org/freedesktop/NetworkManager/AccessPoint/485".into(),
            ssid: Ssid::new(b"Toursanak".to_vec()),
            strength,
            frequency: 2457,
            hw_address: "68:CC:6E:CA:07:F0".into(),
            max_bitrate: 130000,
            bandwidth: 20,
            security: Security {
                flags: 1,
                wpa: 332,
                rsn: 332,
            },
            last_seen: 15238,
            active: true,
        }
    }

    /// This seat, as read while the job ran: wifi up, no wired device at all.
    fn this_seat() -> NetworkState {
        NetworkState {
            available: true,
            version: "1.58.0".into(),
            state: NmState::ConnectedGlobal,
            connectivity: Connectivity::Full,
            wifi: WifiState {
                present: true,
                enabled: true,
                status: WifiStatus::Connected,
                device_state: DeviceState::Activated,
                networks: vec![associated(94)],
                active: Some(associated(94)),
                ..WifiState::default()
            },
            wired: Vec::new(),
            primary: Some(ActiveConnection {
                path: "/org/freedesktop/NetworkManager/ActiveConnection/25".into(),
                id: "Toursanak".into(),
                uuid: "374d5e77-0c73-4c75-aeeb-511e537593bd".into(),
                kind: "802-11-wireless".into(),
                state: ActiveState::Activated,
                default_route: true,
                vpn: false,
                settings_path: "/org/freedesktop/NetworkManager/Settings/34".into(),
                devices: vec!["/org/freedesktop/NetworkManager/Devices/2".into()],
            }),
            active_connections: Vec::new(),
            poll_rate: PollRate::NORMAL,
        }
    }

    #[test]
    fn the_qml_derived_properties_come_out_of_the_state_this_seat_reported() {
        let state = this_seat();
        assert!(!state.ethernet());
        assert!(state.connected());
        assert_eq!(state.network_name(), "Toursanak");
        assert_eq!(state.network_strength(), 94);
        assert!(!state.captive_portal());
    }

    #[test]
    fn a_cable_carries_connected_even_with_the_radio_off() {
        let mut state = this_seat();
        state.wifi.enabled = false;
        state.wifi.status = WifiStatus::Disabled;
        state.wired = vec![wired(DeviceState::Activated, true)];
        assert!(state.ethernet());
        assert!(state.connected());
    }

    /// `Network.qml:37` requires the status word `connected`, so a portal is not it.
    #[test]
    fn a_portal_is_not_connected_but_is_reported_as_a_portal() {
        let mut state = this_seat();
        state.connectivity = Connectivity::Portal;
        state.wifi.status = WifiStatus::Limited;
        assert!(!state.connected());
        assert!(state.captive_portal());
    }

    #[test]
    fn a_cable_in_the_socket_that_never_came_up_is_carrier_without_connected() {
        let link = wired(DeviceState::Disconnected, true);
        assert!(link.carrier);
        assert!(!link.connected());
    }

    #[test]
    fn no_active_connection_leaves_the_name_empty_rather_than_guessing() {
        let mut state = this_seat();
        state.primary = None;
        assert_eq!(state.network_name(), "");
        assert_eq!(NetworkState::default().network_strength(), 0);
    }
}
