//! Crate state to the JSON in `PROTOCOL.md`.
//!
//! Written out by hand rather than derived, so a field rename inside a crate is a
//! compile error here instead of a silent protocol break at the consumer.

use koompi_bluetooth::{Adapter, BluetoothState, Device, RfkillEntry, RfkillState};
use koompi_brightness::{BrightnessState, Panel};
use koompi_hyprland::HyprlandState;
use koompi_network::{AccessPoint, ActiveConnection, NetworkState, Ssid, WifiState, WiredDevice};
use koompi_power::{Battery, ChargeThreshold, PowerState, Profiles};
use serde_json::{json, Value};

pub fn network(state: &NetworkState) -> Value {
    json!({
        "available": state.available,
        "version": state.version,
        "state": state.state.as_str(),
        "connectivity": state.connectivity.as_str(),
        "wifi": wifi(&state.wifi),
        "wired": state.wired.iter().map(wired).collect::<Vec<_>>(),
        "primary": state.primary.as_ref().map(active_connection),
        "active_connections": state.active_connections.iter().map(active_connection).collect::<Vec<_>>(),
        "ethernet": state.ethernet(),
        "connected": state.connected(),
        "network_name": state.network_name(),
        "network_strength": state.network_strength(),
        "captive_portal": state.captive_portal(),
    })
}

fn wifi(wifi: &WifiState) -> Value {
    json!({
        "present": wifi.present,
        "enabled": wifi.enabled,
        "status": wifi.status.as_str(),
        "scanning": wifi.scanning,
        "connecting": wifi.connecting,
        "connect_target": wifi.connect_target.as_ref().map(ssid),
        "interface": wifi.interface,
        "hw_address": wifi.hw_address,
        "device_state": wifi.device_state.as_str(),
        "bitrate": wifi.bitrate,
        "last_scan": wifi.last_scan,
        "networks": wifi.networks.iter().map(access_point).collect::<Vec<_>>(),
        "networks_by_ssid": wifi.networks_by_ssid().iter().map(access_point).collect::<Vec<_>>(),
        "active": wifi.active.as_ref().map(access_point),
    })
}

fn ssid(value: &Ssid) -> Value {
    json!({"ssid": value.to_lossy(), "ssid_hex": hex(value.as_bytes())})
}

fn access_point(ap: &AccessPoint) -> Value {
    json!({
        "path": ap.path,
        "ssid": ap.ssid.to_lossy(),
        "ssid_hex": hex(ap.ssid.as_bytes()),
        "ssid_valid_utf8": ap.ssid.is_utf8(),
        "strength": ap.strength,
        "frequency": ap.frequency,
        "band_ghz": ap.band_ghz(),
        "hw_address": ap.hw_address,
        "max_bitrate": ap.max_bitrate,
        "bandwidth": ap.bandwidth,
        "security": {
            "label": ap.security.label(),
            "open": ap.security.open(),
            "wants_psk": ap.security.wants_psk(),
            "enterprise": ap.security.enterprise(),
            "wpa3": ap.security.wpa3(),
            "owe": ap.security.owe(),
        },
        "last_seen": ap.last_seen,
        "active": ap.active,
    })
}

fn wired(link: &WiredDevice) -> Value {
    json!({
        "interface": link.device.interface,
        "state": link.device.state.as_str(),
        "connected": link.connected(),
        "carrier": link.carrier,
        "speed": link.speed,
        "hw_address": link.hw_address,
    })
}

fn active_connection(connection: &ActiveConnection) -> Value {
    json!({
        "path": connection.path,
        "id": connection.id,
        "uuid": connection.uuid,
        "kind": connection.kind,
        "state": connection.state.as_str(),
        "default_route": connection.default_route,
        "vpn": connection.vpn,
    })
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn power(state: &PowerState) -> Value {
    json!({
        "on_battery": state.on_battery,
        "plugged_in": state.plugged_in,
        "display": state.display.as_ref().map(battery),
        "batteries": state.batteries.iter().map(battery).collect::<Vec<_>>(),
        "primary": state.primary().map(battery),
        "profiles": state.profiles.as_ref().map(profiles),
    })
}

fn battery(pack: &Battery) -> Value {
    json!({
        "native_path": pack.native_path,
        "present": pack.present,
        "state": pack.state.as_str(),
        "charging": pack.charging,
        "percentage": pack.percentage,
        "low": pack.low,
        "critical": pack.critical,
        "full": pack.full,
        "energy": pack.energy,
        "energy_full": pack.energy_full,
        "energy_full_design": pack.energy_full_design,
        "energy_rate": pack.energy_rate,
        "time_to_empty": pack.time_to_empty,
        "time_to_full": pack.time_to_full,
        "health": pack.health,
        "cycle_count": pack.cycle_count,
        "warning": pack.warning.as_str(),
        "icon_name": pack.icon_name,
        "threshold": threshold(&pack.threshold),
    })
}

fn threshold(limit: &ChargeThreshold) -> Value {
    json!({
        "supported": limit.supported,
        "enabled": limit.enabled,
        "start": limit.start,
        "end": limit.end,
    })
}

fn profiles(profiles: &Profiles) -> Value {
    json!({
        "active": profiles.active.map(|p| p.as_str()),
        "available": profiles.available.iter().map(|p| p.as_str()).collect::<Vec<_>>(),
        "degraded": profiles.degraded,
    })
}

/// `brightness` is the fraction every consumer binds to; `raw` and `raw_max` are beside it
/// because a `set_brightness` of the same fraction can land on a different raw value, and
/// a consumer showing a step count needs the panel's own resolution to say how many.
pub fn brightness(state: &BrightnessState) -> Value {
    json!({
        "panels": state.panels.iter().map(panel).collect::<Vec<_>>(),
    })
}

fn panel(panel: &Panel) -> Value {
    json!({
        "id": panel.id,
        "connector": panel.connector,
        "backend": panel.backend.as_str(),
        "brightness": panel.fraction(),
        "raw": panel.raw,
        "raw_max": panel.raw_max,
        "bus": panel.bus,
    })
}

/// `powered` and `connected` are the two the bar binds to, and both were a `.values`
/// scan in JavaScript over a model Quickshell rebuilt on every BlueZ signal.
pub fn bluetooth(state: &BluetoothState) -> Value {
    json!({
        "available": state.available(),
        "powered": state.powered(),
        "discovering": state.discovering(),
        "connected": state.connected().next().is_some(),
        "connected_count": state.connected().count(),
        "adapter": state.default_adapter().map(adapter),
        "adapters": state.adapters.iter().map(adapter).collect::<Vec<_>>(),
        "devices": state.devices.iter().map(device).collect::<Vec<_>>(),
        "rfkill": rfkill(&state.rfkill),
    })
}

fn adapter(adapter: &Adapter) -> Value {
    json!({
        "path": adapter.path,
        "id": adapter.id,
        "address": adapter.address,
        "name": adapter.name,
        "alias": adapter.alias,
        "powered": adapter.powered,
        "power_state": adapter.power_state.as_str(),
        "discoverable": adapter.discoverable,
        "discovering": adapter.discovering,
        "pairable": adapter.pairable,
    })
}

fn device(device: &Device) -> Value {
    json!({
        "path": device.path,
        "adapter": device.adapter,
        "address": device.address,
        "name": device.name,
        "alias": device.alias,
        "paired": device.paired,
        "trusted": device.trusted,
        "connected": device.connected,
        "blocked": device.blocked,
        "icon": device.icon,
        "rssi": device.rssi,
        "battery": device.battery,
    })
}

fn rfkill(state: &RfkillState) -> Value {
    json!({
        "soft_blocked": state.soft_blocked(),
        "hard_blocked": state.hard_blocked(),
        "entries": state.entries.iter().map(rfkill_entry).collect::<Vec<_>>(),
    })
}

fn rfkill_entry(entry: &RfkillEntry) -> Value {
    json!({
        "index": entry.index,
        "kind": entry.kind.as_str(),
        "name": entry.name,
        "soft_blocked": entry.soft_blocked,
        "hard_blocked": entry.hard_blocked,
    })
}

/// The objects go out as the compositor writes them, field for field, because every
/// consumer here was reading `hyprctl -j` output an hour ago. Only the top level, which
/// no `hyprctl` call ever produced, is named here.
pub fn hyprland(state: &HyprlandState) -> Value {
    json!({
        "connected": state.connected,
        "windows": value(&state.windows),
        "workspaces": value(&state.workspaces),
        "workspaces_numbered": value(&state.numbered_workspaces().collect::<Vec<_>>()),
        "active_workspace": value(&state.active_workspace),
        "active_window": value(&state.active_window),
        "monitors": value(&state.monitors),
        "layers": value(&state.layers),
    })
}

/// A float the compositor reported as NaN would otherwise panic the whole daemon.
fn value<T: serde::Serialize>(item: &T) -> Value {
    serde_json::to_value(item).unwrap_or(Value::Null)
}

#[cfg(test)]
mod tests {
    use super::*;
    use koompi_hyprland::{Client, Monitor, Workspace};
    use koompi_network::{Security, WifiStatus};

    fn ap(bytes: &[u8], strength: u8) -> AccessPoint {
        AccessPoint {
            path: "/org/freedesktop/NetworkManager/AccessPoint/1".into(),
            ssid: Ssid::new(bytes.to_vec()),
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

    #[test]
    fn an_ssid_that_is_not_utf8_keeps_its_bytes_in_hex_and_says_the_string_is_lossy() {
        let value = access_point(&ap(&[0xff, 0xfe, b'x'], 90));
        assert_eq!(value["ssid_hex"], json!("fffe78"));
        assert_eq!(value["ssid_valid_utf8"], json!(false));
        assert_ne!(value["ssid"], json!("\u{fffd}\u{fffd}x".to_string() + "!"));
    }

    #[test]
    fn a_utf8_ssid_round_trips_and_is_still_addressable_by_hex() {
        let value = access_point(&ap("Toursanak".as_bytes(), 94));
        assert_eq!(value["ssid"], json!("Toursanak"));
        assert_eq!(value["ssid_valid_utf8"], json!(true));
        assert_eq!(value["ssid_hex"], json!("546f757273616e616b"));
    }

    /// The QML would otherwise recompute these in JavaScript, which is the bug
    /// `network/src/model.rs` exists to remove.
    #[test]
    fn the_derived_properties_the_qml_binds_to_are_all_on_the_wire() {
        let mut state = NetworkState {
            available: true,
            ..NetworkState::default()
        };
        state.wifi.enabled = true;
        state.wifi.status = WifiStatus::Connected;
        state.wifi.active = Some(ap("Toursanak".as_bytes(), 94));

        let value = network(&state);
        assert_eq!(value["connected"], json!(true));
        assert_eq!(value["ethernet"], json!(false));
        assert_eq!(value["network_strength"], json!(94));
        assert_eq!(value["network_name"], json!(""));
        assert_eq!(value["captive_portal"], json!(false));
    }

    #[test]
    fn a_threshold_a_pack_does_not_support_still_reports_every_field() {
        let value = threshold(&ChargeThreshold::default());
        assert_eq!(value["supported"], json!(false));
        assert_eq!(value["start"], json!(0));
        assert_eq!(value["end"], json!(0));
    }

    /// A rename in the crate is a rename at `OverviewWidget.qml`, which reads these
    /// objects exactly as `hyprctl -j` printed them.
    #[test]
    fn the_hyprland_objects_go_out_under_the_compositors_own_field_names() {
        let state = HyprlandState {
            windows: vec![Client {
                address: "0x1".into(),
                initial_class: "kitty".into(),
                size: [800, 600],
                ..Default::default()
            }],
            monitors: vec![Monitor {
                name: "eDP-1".into(),
                refresh_rate: 60.0,
                ..Default::default()
            }],
            workspaces: vec![Workspace {
                id: 1,
                monitor_id: 0,
                ..Default::default()
            }],
            ..Default::default()
        };

        let value = hyprland(&state);
        assert_eq!(value["windows"][0]["initialClass"], json!("kitty"));
        assert_eq!(value["windows"][0]["size"], json!([800, 600]));
        assert_eq!(value["windows"][0]["workspace"]["id"], json!(0));
        assert_eq!(value["monitors"][0]["refreshRate"], json!(60.0));
        assert_eq!(value["monitors"][0]["activeWorkspace"]["name"], json!(""));
        assert_eq!(value["workspaces"][0]["monitorID"], json!(0));
    }

    /// `HyprlandData.qml` never published the lock screen's workspace at 2147483646, and a
    /// bar that started drawing it would draw it off the end of the row.
    #[test]
    fn both_the_whole_workspace_list_and_the_numbered_view_are_sent() {
        let state = HyprlandState {
            workspaces: vec![
                Workspace {
                    id: 1,
                    ..Default::default()
                },
                Workspace {
                    id: -98,
                    name: "special:scratch".into(),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };

        let value = hyprland(&state);
        assert_eq!(value["workspaces"].as_array().map(Vec::len), Some(2));
        assert_eq!(
            value["workspaces_numbered"].as_array().map(Vec::len),
            Some(1)
        );
        assert_eq!(value["workspaces_numbered"][0]["id"], json!(1));
    }

    fn headset(connected: bool, battery: Option<u8>) -> Device {
        Device {
            path: "/org/bluez/hci0/dev_AC_80_0A_11_22_33".into(),
            adapter: "/org/bluez/hci0".into(),
            address: "AC:80:0A:11:22:33".into(),
            name: None,
            alias: "AC-80-0A-11-22-33".into(),
            paired: true,
            trusted: false,
            connected,
            blocked: false,
            icon: Some("audio-headset".into()),
            rssi: Some(-54),
            battery,
        }
    }

    /// `BluetoothStatus.qml` sorted on `name` and got the dashed address for a device
    /// BlueZ never learned one for. Keeping both fields is what lets the consumer show
    /// `alias` and still know the name is missing.
    #[test]
    fn a_nameless_device_sends_a_null_name_beside_the_alias_that_stands_in_for_it() {
        let value = device(&headset(true, None));

        assert_eq!(value["name"], json!(null));
        assert_eq!(value["alias"], json!("AC-80-0A-11-22-33"));
        assert_eq!(value["battery"], json!(null));
    }

    /// A percentage, not the 0..1 fraction `Quickshell.Bluetooth` published, which every
    /// consumer multiplied back up by 100.
    #[test]
    fn a_battery_goes_out_as_the_percentage_bluez_reports() {
        assert_eq!(device(&headset(true, Some(80)))["battery"], json!(80));
    }

    /// The `.values.some(...)` scans at `BluetoothStatus.qml:34` and `:47`.
    #[test]
    fn the_connected_flags_the_bar_binds_to_are_counted_here_not_in_javascript() {
        let state = BluetoothState {
            devices: vec![headset(true, None), headset(false, None)],
            ..Default::default()
        };

        let value = bluetooth(&state);
        assert_eq!(value["connected"], json!(true));
        assert_eq!(value["connected_count"], json!(1));
        // no adapter on this seat, and that is a working seat rather than an outage
        assert_eq!(value["available"], json!(false));
        assert_eq!(value["powered"], json!(false));
        assert_eq!(value["adapter"], json!(null));
    }

    #[test]
    fn hex_is_lowercase_and_zero_padded() {
        assert_eq!(hex(&[0x00, 0x0f, 0xa0]), "000fa0");
        assert_eq!(hex(&[]), "");
    }
}
