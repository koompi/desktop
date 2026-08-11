//! D16 session and logind: seat and session state, the sleep and hibernate
//! capabilities the QML asks `busctl` for, inhibitor locks as file descriptors, and
//! the nine calls that change the machine.
//!
//! Three subprocesses go away. `SessionWarnings.qml:43-51` runs `busctl` and greps its
//! output for `"(yes|challenge)"`; `Idle.qml:53-58` keeps a
//! `systemd-inhibit ... sleep infinity` alive purely to hold an fd, and
//! `Idle.qml:20,24,34` releases it with `pkill -f` on a pattern.
//!
//! ## Reading is safe here and calling is not
//!
//! Everything a consumer can subscribe to is a read. The nine methods that end a
//! session or power the machine off are built in [`action`] and reachable through one
//! function, [`Call::send`], so the dangerous surface is a single call site rather
//! than a proxy full of plausible typos. [`Call::strands_the_seat`] marks the one this
//! repo has already been bitten by.
//!
//! ## Locking before the machine sleeps
//!
//! Set [`SessionConfig::delay_sleep`] and the service holds a `delay` inhibitor on
//! `sleep`. When `PrepareForSleep(true)` arrives, the inhibitor is handed to every
//! subscriber inside the event, so logind waits until the last subscriber has dropped
//! it - up to the manager's `InhibitDelayMaxUSec`, five seconds on this seat. Raise
//! the lock screen, then drop the hold. The inhibitor is re-taken once the machine is
//! back.
//!
//! ```no_run
//! # async fn run() -> koompi_service::Result<()> {
//! use koompi_session::{SessionConfig, SessionEvent, SessionService};
//!
//! let service = SessionService::connect(SessionConfig {
//!     delay_sleep: Some("Lock the screen before sleeping".into()),
//!     ..SessionConfig::default()
//! })
//! .await?;
//!
//! let mut events = service.events();
//! while let Ok(event) = events.recv().await {
//!     if let SessionEvent::PrepareForSleep { going_to_sleep: true, hold } = event {
//!         // raise the lock screen here
//!         service.set_locked_hint(true).await?;
//!         drop(hold);
//!     }
//! }
//! # Ok(()) }
//! ```

mod action;
mod capability;
mod inhibit;
mod props;
mod proxy;
mod service;
mod state;

pub use action::{Call, PowerAction, SessionAction};
pub use capability::{Capabilities, Capability};
pub use inhibit::{ActiveInhibitor, Inhibitor, Mode, What};
pub use service::{DelayHold, SessionEvent, SessionService};
pub use state::{SeatInfo, SessionInfo, SessionState};

pub use koompi_service::{Error, Result};

use std::time::Duration;

use koompi_service::PollRate;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionConfig {
    /// The `who` every inhibitor this service takes is tagged with, and what
    /// `systemd-inhibit --list` shows. `Idle.qml:57` uses `quickshell`.
    pub who: String,
    /// The `why` for a `delay` inhibitor on `sleep`, held so a consumer can lock the
    /// screen before the machine goes down. `None` takes no lock at all.
    pub delay_sleep: Option<String>,
    /// Which session to follow. `None` reads `XDG_SESSION_ID`, then asks logind which
    /// session this process is in.
    pub session_id: Option<String>,
    /// Starting value of the shell-wide multiplier from `PowerSaving.qml:33`. Push
    /// changes in with [`SessionService::set_poll_rate`].
    pub poll_rate: PollRate,
    /// How often to re-read the six capabilities. logind signals inhibitor changes, so
    /// this exists only for what it does not signal: a polkit policy edit can turn
    /// `yes` into `challenge` with nothing on the bus to say so.
    pub capability_refresh: Duration,
}

impl Default for SessionConfig {
    fn default() -> Self {
        Self {
            who: "koompi-shell".to_owned(),
            delay_sleep: None,
            session_id: None,
            poll_rate: PollRate::NORMAL,
            capability_refresh: Duration::from_secs(60),
        }
    }
}
