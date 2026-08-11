//! The methods only. Every read arrives through the object manager, so nothing here
//! declares a property except the two the crate writes.

use zvariant::ObjectPath;

#[zbus::proxy(
    interface = "org.bluez.Adapter1",
    default_service = "org.bluez",
    assume_defaults = false
)]
pub trait Adapter {
    fn start_discovery(&self) -> zbus::Result<()>;

    fn stop_discovery(&self) -> zbus::Result<()>;

    fn remove_device(&self, device: &ObjectPath<'_>) -> zbus::Result<()>;

    #[zbus(property)]
    fn set_powered(&self, powered: bool) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.bluez.Device1",
    default_service = "org.bluez",
    assume_defaults = false
)]
pub trait Device {
    fn connect(&self) -> zbus::Result<()>;

    fn disconnect(&self) -> zbus::Result<()>;

    fn pair(&self) -> zbus::Result<()>;

    fn cancel_pairing(&self) -> zbus::Result<()>;

    #[zbus(property)]
    fn set_trusted(&self, trusted: bool) -> zbus::Result<()>;
}
