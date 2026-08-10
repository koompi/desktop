//! Only the methods and the one writable property. Every read goes through
//! `org.freedesktop.DBus.Properties.GetAll`, which is one round trip per object and
//! cannot hand back a half-updated view the way a per-property cache can.

use zvariant::OwnedObjectPath;

#[zbus::proxy(
    interface = "org.freedesktop.UPower",
    default_service = "org.freedesktop.UPower",
    default_path = "/org/freedesktop/UPower"
)]
pub trait UPower {
    fn enumerate_devices(&self) -> zbus::Result<Vec<OwnedObjectPath>>;

    fn get_display_device(&self) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(
    interface = "org.freedesktop.UPower.Device",
    default_service = "org.freedesktop.UPower"
)]
pub trait Device {
    fn enable_charge_threshold(&self, enable: bool) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.freedesktop.UPower.PowerProfiles",
    default_service = "org.freedesktop.UPower.PowerProfiles",
    default_path = "/org/freedesktop/UPower/PowerProfiles"
)]
pub trait PowerProfiles {
    #[zbus(property)]
    fn set_active_profile(&self, profile: &str) -> zbus::Result<()>;
}
