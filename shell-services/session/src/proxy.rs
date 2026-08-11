//! Reads, lookups, `Inhibit` and the two manager signals.
//!
//! The nine methods that change something are deliberately absent: they live in
//! [`crate::action`] behind one `send`, so there is no proxy handle on which
//! `power_off()` is a plausible typo.

use zvariant::{OwnedFd, OwnedObjectPath};

pub const LOGIN1: &str = "org.freedesktop.login1";
pub const MANAGER_PATH: &str = "/org/freedesktop/login1";
pub const MANAGER_IFACE: &str = "org.freedesktop.login1.Manager";
pub const SESSION_IFACE: &str = "org.freedesktop.login1.Session";
pub const SEAT_IFACE: &str = "org.freedesktop.login1.Seat";

/// The `(what, who, why, mode, uid, pid)` row `ListInhibitors` answers with.
pub type InhibitorRow = (String, String, String, String, u32, u32);

#[zbus::proxy(
    interface = "org.freedesktop.login1.Manager",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1"
)]
pub trait Manager {
    fn get_session(&self, id: &str) -> zbus::Result<OwnedObjectPath>;

    #[zbus(name = "GetSessionByPID")]
    fn get_session_by_pid(&self, pid: u32) -> zbus::Result<OwnedObjectPath>;

    fn can_power_off(&self) -> zbus::Result<String>;
    fn can_reboot(&self) -> zbus::Result<String>;
    fn can_suspend(&self) -> zbus::Result<String>;
    fn can_hibernate(&self) -> zbus::Result<String>;
    fn can_hybrid_sleep(&self) -> zbus::Result<String>;
    fn can_suspend_then_hibernate(&self) -> zbus::Result<String>;

    /// Answers with the lock itself. The lock lasts exactly as long as the fd is open.
    fn inhibit(&self, what: &str, who: &str, why: &str, mode: &str) -> zbus::Result<OwnedFd>;

    fn list_inhibitors(&self) -> zbus::Result<Vec<InhibitorRow>>;

    /// True on the way down, false on the way back up. A `delay` inhibitor held while
    /// the true arrives is the window in which a screen lock can be raised.
    #[zbus(signal)]
    fn prepare_for_sleep(&self, start: bool) -> zbus::Result<()>;

    #[zbus(signal)]
    fn prepare_for_shutdown(&self, start: bool) -> zbus::Result<()>;
}

/// Only the two signals. Every property this crate reads comes through `GetAll`.
#[zbus::proxy(
    interface = "org.freedesktop.login1.Session",
    default_service = "org.freedesktop.login1"
)]
pub trait Session {
    /// logind asking the session to lock, which is what `loginctl lock-session` sends.
    #[zbus(signal)]
    fn lock(&self) -> zbus::Result<()>;

    #[zbus(signal)]
    fn unlock(&self) -> zbus::Result<()>;
}
