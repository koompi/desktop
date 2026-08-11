//! The two interfaces this crate calls out to. Item properties are not here: they come in
//! one `GetAll` per item so a read cannot hand back a half-updated icon.

#[zbus::proxy(
    interface = "org.kde.StatusNotifierWatcher",
    default_service = "org.kde.StatusNotifierWatcher",
    default_path = "/StatusNotifierWatcher"
)]
pub trait StatusNotifierWatcher {
    fn register_status_notifier_item(&self, service: &str) -> zbus::Result<()>;

    fn register_status_notifier_host(&self, service: &str) -> zbus::Result<()>;

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> zbus::Result<Vec<String>>;

    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> zbus::Result<bool>;

    #[zbus(property)]
    fn protocol_version(&self) -> zbus::Result<i32>;
}

#[zbus::proxy(interface = "org.kde.StatusNotifierItem")]
pub trait StatusNotifierItem {
    fn activate(&self, x: i32, y: i32) -> zbus::Result<()>;

    fn secondary_activate(&self, x: i32, y: i32) -> zbus::Result<()>;

    fn context_menu(&self, x: i32, y: i32) -> zbus::Result<()>;

    /// `orientation` is "vertical" or "horizontal".
    fn scroll(&self, delta: i32, orientation: &str) -> zbus::Result<()>;
}
