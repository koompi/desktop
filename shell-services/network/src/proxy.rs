//! Only the methods. Every read goes through `org.freedesktop.DBus.Properties.GetAll`,
//! one round trip per object, so no consumer ever sees a half-updated access point.

use std::collections::HashMap;

use zvariant::{ObjectPath, OwnedObjectPath, OwnedValue};

/// `a{sa{sv}}`: setting name to key to value, the shape every connection profile takes
/// on this bus.
pub type ConnectionSettings = HashMap<String, HashMap<String, OwnedValue>>;

pub const NM: &str = "org.freedesktop.NetworkManager";
pub const NM_PATH: &str = "/org/freedesktop/NetworkManager";
pub const MANAGER_IFACE: &str = "org.freedesktop.NetworkManager";
pub const DEVICE_IFACE: &str = "org.freedesktop.NetworkManager.Device";
pub const WIRELESS_IFACE: &str = "org.freedesktop.NetworkManager.Device.Wireless";
pub const WIRED_IFACE: &str = "org.freedesktop.NetworkManager.Device.Wired";
pub const AP_IFACE: &str = "org.freedesktop.NetworkManager.AccessPoint";
pub const ACTIVE_IFACE: &str = "org.freedesktop.NetworkManager.Connection.Active";

#[zbus::proxy(
    interface = "org.freedesktop.NetworkManager",
    default_service = "org.freedesktop.NetworkManager",
    default_path = "/org/freedesktop/NetworkManager"
)]
pub trait NetworkManager {
    fn get_devices(&self) -> zbus::Result<Vec<OwnedObjectPath>>;

    /// `Network.qml:76` shells `nmcli dev wifi connect <ssid>` for exactly this, and
    /// says so in its own comment: it creates the profile as well as activating it.
    fn add_and_activate_connection(
        &self,
        connection: &ConnectionSettings,
        device: &ObjectPath<'_>,
        specific_object: &ObjectPath<'_>,
    ) -> zbus::Result<(OwnedObjectPath, OwnedObjectPath)>;

    /// `Network.qml:81`, `nmcli connection down <ssid>`.
    fn deactivate_connection(&self, active_connection: &ObjectPath<'_>) -> zbus::Result<()>;

    /// `Network.qml:60`, `nmcli radio wifi on|off`.
    #[zbus(property)]
    fn set_wireless_enabled(&self, enabled: bool) -> zbus::Result<()>;

    #[zbus(property)]
    fn wireless_enabled(&self) -> zbus::Result<bool>;
}

#[zbus::proxy(
    interface = "org.freedesktop.NetworkManager.Device.Wireless",
    default_service = "org.freedesktop.NetworkManager"
)]
pub trait DeviceWireless {
    fn get_all_access_points(&self) -> zbus::Result<Vec<OwnedObjectPath>>;

    /// `Network.qml:147`, `nmcli dev wifi list --rescan yes`. The one write here that
    /// is safe to fire: the shell already triggers it from a button.
    fn request_scan(&self, options: &HashMap<String, OwnedValue>) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.freedesktop.NetworkManager.Settings.Connection",
    default_service = "org.freedesktop.NetworkManager"
)]
pub trait SettingsConnection {
    fn get_settings(&self) -> zbus::Result<ConnectionSettings>;

    /// `Network.qml:96`, `nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"`.
    /// Never called against this seat: a wrong PSK written here locks the user out of
    /// their own network.
    fn update(&self, settings: &ConnectionSettings) -> zbus::Result<()>;
}
