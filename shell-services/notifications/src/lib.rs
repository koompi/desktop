//! D06 notification server and D07 persistence: the server side of the spec, so actions,
//! hints, `replaces_id` and inline image data all land here.
//!
//! `Notifications.qml:150-165` declares Quickshell's builtin `NotificationServer`, which
//! owns `org.freedesktop.Notifications` and does this work in C++. This is that server.
//!
//! **Serving the interface and owning the name are two separate calls.**
//! [`NotificationService::serve`] exports the object and takes nothing;
//! [`NotificationService::own_name`] claims the name, and on a seat where the shell already
//! has it that call fails rather than displacing it, because a second owner means the user
//! stops seeing notifications at all. The demo runs under `dbus-run-session` for that
//! reason, and so does every test in here that touches a bus.
//!
//! Images are forwarded exactly as the application sent them: dimensions, stride and bytes.
//! Nothing here decodes, rescales or writes an image, which is what keeps a drawing crate
//! out of this dependency graph.
//!
//! Where applications disagree with the spec, the lenient reading wins: a hint that will not
//! decode is dropped, never the notification carrying it.

mod hints;
mod model;
mod server;
mod service;
mod store;

pub use hints::Hints;
pub use model::{Action, CloseReason, Icon, ImageData, Notification, Timeout, Urgency};
pub use service::{
    NotificationEvent, NotificationService, NotificationsState, BUS_NAME, OBJECT_PATH,
};
pub use store::Store;

use std::path::PathBuf;
use std::time::Duration;

use koompi_service::PollRate;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotificationsConfig {
    /// The popup life for a sender that asked for the server default, `expire_timeout` of
    /// `-1`. `Notifications.qml:64` is 7000 ms and this matches it.
    pub default_timeout: Duration,

    /// The one timer in this crate is the popup's, and `PowerSaving.qml:33` stretches it
    /// like every other: a seat on battery holds a popup twice as long rather than waking
    /// twice as often to take it down.
    pub poll_rate: PollRate,

    /// `Directories.qml:36`. The user's notification history lives here and nothing else
    /// writes it.
    pub history_path: PathBuf,

    /// Answered to `GetCapabilities`, and answered honestly: this is a claim about what the
    /// consumer draws, not about what the wire supports. The default is the flag block at
    /// `Notifications.qml:150-165`, where `actionIconsSupported` is commented out and so
    /// `action-icons` is absent here too.
    pub capabilities: Vec<String>,
}

impl Default for NotificationsConfig {
    fn default() -> Self {
        Self {
            default_timeout: Duration::from_millis(7000),
            poll_rate: PollRate::NORMAL,
            history_path: Store::default_path(),
            capabilities: [
                "actions",
                "body",
                "body-hyperlinks",
                "body-images",
                "body-markup",
                "icon-static",
                "persistence",
            ]
            .iter()
            .map(|capability| (*capability).to_owned())
            .collect(),
        }
    }
}
