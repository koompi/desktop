//! D09 item 2. What a signal actually invalidated.
//!
//! `Network.qml:164-175` keeps `nmcli monitor` alive forever and re-runs all five of its
//! queries on any line it prints, so an access point two rooms away nudging its signal
//! strength costs the shell five processes. The bus already says which object changed and
//! which properties on it; this is the mapping from that to the reads worth doing.

use crate::proxy::{ACTIVE_IFACE, AP_IFACE, DEVICE_IFACE, MANAGER_IFACE, WIRED_IFACE, WIRELESS_IFACE};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Refresh {
    /// The manager's own properties: state, connectivity, the wireless kill switch.
    pub manager: bool,
    /// Re-enumerate the device list.
    pub devices: bool,
    /// The wireless device's own properties.
    pub wifi: bool,
    /// Every wired device's own properties.
    pub wired: bool,
    /// Re-enumerate the access point list.
    pub access_points: bool,
    /// Re-read only the access point the signal arrived from.
    pub access_point: bool,
    /// The active connection list.
    pub active: bool,
}

impl Refresh {
    pub const NONE: Self = Self {
        manager: false,
        devices: false,
        wifi: false,
        wired: false,
        access_points: false,
        access_point: false,
        active: false,
    };

    pub const ALL: Self = Self {
        manager: true,
        devices: true,
        wifi: true,
        wired: true,
        access_points: true,
        access_point: false,
        active: true,
    };

    pub fn merge(&mut self, other: Self) {
        self.manager |= other.manager;
        self.devices |= other.devices;
        self.wifi |= other.wifi;
        self.wired |= other.wired;
        self.access_points |= other.access_points;
        self.access_point |= other.access_point;
        self.active |= other.active;
    }

    pub fn is_empty(&self) -> bool {
        *self == Self::NONE
    }
}

/// A device appearing or disappearing invalidates everything hanging off the device list.
const DEVICE_LIST: Refresh = Refresh {
    devices: true,
    wifi: true,
    wired: true,
    access_points: true,
    ..Refresh::NONE
};

/// `PropertiesChanged`: the interface it names, and the keys it carries.
///
/// An interface this crate does not model changes nothing here. That is deliberate:
/// `IP4Config`, `DHCP4Config`, `Device.Statistics` and `DnsManager` all emit on this bus
/// during an ordinary connection, and they are the bulk of what made `nmcli monitor`
/// expensive.
pub fn refresh_for_properties(interface: &str, keys: &[&str]) -> Refresh {
    let mut refresh = Refresh::NONE;
    match interface {
        MANAGER_IFACE => {
            for key in keys {
                refresh.merge(match *key {
                    "Devices" | "AllDevices" => DEVICE_LIST,
                    "ActiveConnections" | "PrimaryConnection" | "PrimaryConnectionType" => Refresh {
                        active: true,
                        ..Refresh::NONE
                    },
                    "State" | "Connectivity" | "WirelessEnabled" | "NetworkingEnabled"
                    | "WirelessHardwareEnabled" | "Version" => Refresh {
                        manager: true,
                        ..Refresh::NONE
                    },
                    // Metered, Startup, Checkpoints, GlobalDnsConfiguration and the
                    // Wwan/Wimax mirrors of the kill switch. None of them is drawn.
                    _ => Refresh::NONE,
                });
            }
        }
        WIRELESS_IFACE => {
            for key in keys {
                refresh.merge(match *key {
                    "AccessPoints" => Refresh {
                        access_points: true,
                        ..Refresh::NONE
                    },
                    _ => Refresh {
                        wifi: true,
                        ..Refresh::NONE
                    },
                });
            }
        }
        WIRED_IFACE => {
            refresh.wired = !keys.is_empty();
        }
        DEVICE_IFACE => {
            for key in keys {
                refresh.merge(match *key {
                    "Ip4Config" | "Ip6Config" | "Dhcp4Config" | "Dhcp6Config" | "Mtu"
                    | "IpInterface" | "Metered" | "LldpNeighbors" | "Ports" | "Slaves" => {
                        Refresh::NONE
                    }
                    _ => Refresh {
                        wifi: true,
                        wired: true,
                        ..Refresh::NONE
                    },
                });
            }
        }
        AP_IFACE => {
            refresh.access_point = !keys.is_empty();
        }
        ACTIVE_IFACE => {
            for key in keys {
                refresh.merge(match *key {
                    "Ip4Config" | "Ip6Config" | "Dhcp4Config" | "Dhcp6Config" => Refresh::NONE,
                    _ => Refresh {
                        active: true,
                        ..Refresh::NONE
                    },
                });
            }
        }
        _ => {}
    }
    refresh
}

/// The signals NetworkManager emits that are not property changes.
pub fn refresh_for_signal(interface: &str, member: &str) -> Refresh {
    match (interface, member) {
        (MANAGER_IFACE, "DeviceAdded" | "DeviceRemoved") => DEVICE_LIST,
        (MANAGER_IFACE, "StateChanged") => Refresh {
            manager: true,
            active: true,
            ..Refresh::NONE
        },
        (WIRELESS_IFACE, "AccessPointAdded" | "AccessPointRemoved") => Refresh {
            access_points: true,
            wifi: true,
            ..Refresh::NONE
        },
        (DEVICE_IFACE, "StateChanged") => Refresh {
            wifi: true,
            wired: true,
            active: true,
            ..Refresh::NONE
        },
        (ACTIVE_IFACE, "StateChanged") => Refresh {
            active: true,
            ..Refresh::NONE
        },
        _ => Refresh::NONE,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The one that pays for the whole mapping. An access point's `Strength` moves every
    /// few seconds for every neighbour in range; under `nmcli monitor` each of those was
    /// five processes, and here it is one `GetAll` on one object.
    #[test]
    fn a_neighbours_signal_strength_refetches_only_that_access_point() {
        let refresh = refresh_for_properties(AP_IFACE, &["Strength", "LastSeen"]);
        assert!(refresh.access_point);
        assert!(!refresh.access_points);
        assert!(!refresh.manager);
        assert!(!refresh.devices);
        assert!(!refresh.wifi);
        assert!(!refresh.active);
    }

    #[test]
    fn a_dhcp_lease_renewal_refetches_nothing() {
        for interface in [
            "org.freedesktop.NetworkManager.DHCP4Config",
            "org.freedesktop.NetworkManager.IP4Config",
            "org.freedesktop.NetworkManager.Device.Statistics",
            "org.freedesktop.NetworkManager.DnsManager",
        ] {
            let refresh = refresh_for_properties(interface, &["Options", "Addresses"]);
            assert!(refresh.is_empty(), "{interface} woke a read");
        }

        let on_device = refresh_for_properties(DEVICE_IFACE, &["Ip4Config", "Dhcp4Config"]);
        assert!(on_device.is_empty());
    }

    #[test]
    fn the_kill_switch_refetches_the_manager_and_not_the_scan_results() {
        let refresh = refresh_for_properties(MANAGER_IFACE, &["WirelessEnabled"]);
        assert!(refresh.manager);
        assert!(!refresh.access_points);
        assert!(!refresh.devices);
    }

    #[test]
    fn a_new_access_point_reenumerates_the_list_and_a_new_device_reenumerates_everything() {
        let ap = refresh_for_signal(WIRELESS_IFACE, "AccessPointAdded");
        assert!(ap.access_points);
        assert!(!ap.devices);
        assert!(!ap.manager);

        let device = refresh_for_signal(MANAGER_IFACE, "DeviceAdded");
        assert!(device.devices && device.wifi && device.wired && device.access_points);
        assert!(!device.manager);
    }

    #[test]
    fn a_device_changing_state_pulls_the_device_and_its_active_connection() {
        let refresh = refresh_for_signal(DEVICE_IFACE, "StateChanged");
        assert!(refresh.wifi && refresh.wired && refresh.active);
        assert!(!refresh.access_points);
        assert!(!refresh.devices);
    }

    /// A scan landing moves `LastScan` on the wireless interface, not the list.
    #[test]
    fn a_completed_scan_refetches_the_wireless_device_only() {
        let refresh = refresh_for_properties(WIRELESS_IFACE, &["LastScan"]);
        assert!(refresh.wifi);
        assert!(!refresh.access_points);

        let listed = refresh_for_properties(WIRELESS_IFACE, &["AccessPoints", "LastScan"]);
        assert!(listed.access_points && listed.wifi);
    }

    #[test]
    fn a_property_this_crate_has_never_seen_still_refetches_its_own_object() {
        let refresh = refresh_for_properties(WIRELESS_IFACE, &["SomethingNewIn159"]);
        assert!(refresh.wifi);
        assert!(!refresh.devices);

        let manager = refresh_for_properties(MANAGER_IFACE, &["SomethingNewIn159"]);
        assert!(manager.is_empty(), "an unmodelled manager property is not drawn");
    }

    #[test]
    fn merging_accumulates_and_never_clears() {
        let mut refresh = refresh_for_properties(AP_IFACE, &["Strength"]);
        refresh.merge(refresh_for_signal(MANAGER_IFACE, "StateChanged"));
        assert!(refresh.access_point && refresh.manager && refresh.active);
        assert!(!refresh.devices);

        refresh.merge(Refresh::NONE);
        assert!(refresh.access_point && refresh.manager);
        assert!(!Refresh::ALL.is_empty());
        assert!(Refresh::NONE.is_empty());
    }

    #[test]
    fn an_empty_property_set_changes_nothing() {
        for interface in [
            MANAGER_IFACE,
            WIRELESS_IFACE,
            WIRED_IFACE,
            DEVICE_IFACE,
            AP_IFACE,
            ACTIVE_IFACE,
        ] {
            assert!(refresh_for_properties(interface, &[]).is_empty(), "{interface}");
        }
    }
}
