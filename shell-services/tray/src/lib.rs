//! D04 tray host and D05 dbusmenu decode: the StatusNotifierWatcher name ownership, the
//! item host and the menu wire format that Quickshell implements in C++ on our behalf today.
//!
//! Two roles live here and the safe one is the default. [`TrayService`] is a **host**: it
//! registers with whatever watcher already owns `org.kde.StatusNotifierWatcher`, reads the
//! items out of it and proxies each one. It never takes the name, so it runs alongside the
//! shell that owns the tray today without disturbing it. [`WatcherService`] is the other
//! half and has to be asked for by name, because starting one on the session bus is how a
//! desktop loses its tray.
//!
//! Icons are handed on exactly as the application sent them: a theme name, or raw ARGB32
//! bytes with their dimensions. Nothing here decodes, rescales or resolves an icon theme.
//! Which of the two to draw, and how, is the only part of a tray that is a UI decision.

mod item;
mod menu;
mod proxy;
mod service;
mod watcher;

pub use item::{Category, ItemAddress, Pixmap, Status, ToolTip, TrayItem};
pub use menu::{MenuItem, ToggleState, ToggleType};
pub use service::{TrayEvent, TrayService, TrayState};
pub use watcher::{WatcherService, WATCHER_NAME, WATCHER_PATH};

use koompi_service::PollRate;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrayConfig {
    /// This crate has no poll: every read is triggered by a signal. The one timer is the
    /// wait before reconnecting to a watcher that went away, and `PowerSaving.qml:33`
    /// stretches it like every other, so a seat on battery retries a dead tray half as
    /// often.
    pub poll_rate: PollRate,
}

impl Default for TrayConfig {
    fn default() -> Self {
        Self {
            poll_rate: PollRate::NORMAL,
        }
    }
}
