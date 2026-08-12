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
pub const SETTINGS_PATH: &str = "/org/freedesktop/NetworkManager/Settings";

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

    /// The other half of what `nmcli dev wifi connect <ssid>` does: a network the user
    /// has joined before already has a profile holding the passphrase, and adding a
    /// second one asks a secret agent for a key that is on disk.
    fn activate_connection(
        &self,
        connection: &ObjectPath<'_>,
        device: &ObjectPath<'_>,
        specific_object: &ObjectPath<'_>,
    ) -> zbus::Result<OwnedObjectPath>;

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

    /// Only ever called on a profile this crate added moments earlier for an activation
    /// that then failed. `AddAndActivateConnection` persists before it authenticates.
    fn delete(&self) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.freedesktop.NetworkManager.Settings",
    default_service = "org.freedesktop.NetworkManager",
    default_path = "/org/freedesktop/NetworkManager/Settings"
)]
pub trait Settings {
    fn list_connections(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
}

#[zbus::proxy(
    interface = "org.freedesktop.NetworkManager.Connection.Active",
    default_service = "org.freedesktop.NetworkManager"
)]
pub trait ActiveConnection {
    #[zbus(property)]
    fn state(&self) -> zbus::Result<u32>;

    /// The profile behind the activation, read while the object still exists so a
    /// failed attempt can delete what it added.
    #[zbus(property)]
    fn connection(&self) -> zbus::Result<OwnedObjectPath>;
}

/// `StateChanged` in its own trait: the generated `receive_state_changed` for the signal
/// and for the `State` property above cannot share one.
///
/// The signal is the only place the *reason* appears, and the reason is the whole
/// difference between a passphrase the router refused and a radio that went away.
#[zbus::proxy(
    interface = "org.freedesktop.NetworkManager.Connection.Active",
    default_service = "org.freedesktop.NetworkManager"
)]
pub trait ActiveConnectionEvents {
    #[zbus(signal)]
    fn state_changed(&self, state: u32, reason: u32) -> zbus::Result<()>;
}
