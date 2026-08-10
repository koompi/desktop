//! Inhibitor locks as file descriptors, which is what they always were.
//!
//! `Idle.qml:53-58` keeps a `systemd-inhibit ... sleep infinity` process alive because
//! QML cannot hold an fd, and `Idle.qml:20,24,34` then kills it by `pkill -f` on a
//! pattern with a `[q]` in it so the pattern does not match its own command line.
//! Here the lock is the fd, and closing it is releasing it, so both the process and
//! the pattern go away.

use std::fmt;
use std::os::fd::{AsRawFd, OwnedFd};

/// The operations a lock can hold off. A set rather than a string: logind reports
/// `BlockInhibited` as `sleep:idle:handle-lid-switch` while `Idle.qml:57` asks for
/// `idle:sleep:handle-lid-switch`, and those are the same lock.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct What(u8);

impl What {
    pub const NONE: Self = Self(0);
    pub const SHUTDOWN: Self = Self(1 << 0);
    pub const SLEEP: Self = Self(1 << 1);
    pub const IDLE: Self = Self(1 << 2);
    pub const HANDLE_POWER_KEY: Self = Self(1 << 3);
    pub const HANDLE_SUSPEND_KEY: Self = Self(1 << 4);
    pub const HANDLE_HIBERNATE_KEY: Self = Self(1 << 5);
    pub const HANDLE_LID_SWITCH: Self = Self(1 << 6);
    pub const HANDLE_REBOOT_KEY: Self = Self(1 << 7);

    const NAMES: [(Self, &'static str); 8] = [
        (Self::SHUTDOWN, "shutdown"),
        (Self::SLEEP, "sleep"),
        (Self::IDLE, "idle"),
        (Self::HANDLE_POWER_KEY, "handle-power-key"),
        (Self::HANDLE_SUSPEND_KEY, "handle-suspend-key"),
        (Self::HANDLE_HIBERNATE_KEY, "handle-hibernate-key"),
        (Self::HANDLE_LID_SWITCH, "handle-lid-switch"),
        (Self::HANDLE_REBOOT_KEY, "handle-reboot-key"),
    ];

    /// Colon-separated, unknown names dropped. logind's own vocabulary is closed and a
    /// name outside it cannot be re-sent, so keeping it would only let it escape into
    /// an `Inhibit` call that fails.
    pub fn parse(wire: &str) -> Self {
        wire.split(':')
            .filter(|token| !token.is_empty())
            .filter_map(|token| {
                Self::NAMES
                    .iter()
                    .find(|(_, name)| *name == token)
                    .map(|(what, _)| *what)
            })
            .fold(Self::NONE, |set, what| set | what)
    }

    /// Always in logind's own declaration order, so two equal sets spell the same.
    pub fn as_wire(&self) -> String {
        Self::NAMES
            .iter()
            .filter(|(what, _)| self.contains(*what))
            .map(|(_, name)| *name)
            .collect::<Vec<_>>()
            .join(":")
    }

    pub fn contains(&self, other: Self) -> bool {
        self.0 & other.0 == other.0
    }

    pub fn is_empty(&self) -> bool {
        self.0 == 0
    }
}

impl std::ops::BitOr for What {
    type Output = Self;

    fn bitor(self, other: Self) -> Self {
        Self(self.0 | other.0)
    }
}

impl fmt::Display for What {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.as_wire())
    }
}

/// How hard the lock holds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// The operation does not happen while the lock is held.
    Block,
    /// Since systemd 257, a block lock honoured only for other users.
    BlockWeak,
    /// The operation waits for the lock to be released, up to the manager's
    /// `InhibitDelayMaxUSec`. This is the one to hold if you need to lock the screen
    /// before the machine sleeps.
    Delay,
}

impl Mode {
    pub fn as_wire(&self) -> &'static str {
        match self {
            Self::Block => "block",
            Self::BlockWeak => "block-weak",
            Self::Delay => "delay",
        }
    }

    pub fn parse(wire: &str) -> Option<Self> {
        match wire {
            "block" => Some(Self::Block),
            "block-weak" => Some(Self::BlockWeak),
            "delay" => Some(Self::Delay),
            _ => None,
        }
    }
}

/// A lock this process holds. Dropping it closes the fd, which is how logind is told
/// the lock is over; there is nothing to kill and no pattern to match.
pub struct Inhibitor {
    what: What,
    who: String,
    why: String,
    mode: Mode,
    fd: OwnedFd,
}

impl Inhibitor {
    pub(crate) fn new(what: What, who: String, why: String, mode: Mode, fd: OwnedFd) -> Self {
        Self {
            what,
            who,
            why,
            mode,
            fd,
        }
    }

    pub fn what(&self) -> What {
        self.what
    }

    pub fn who(&self) -> &str {
        &self.who
    }

    pub fn why(&self) -> &str {
        &self.why
    }

    pub fn mode(&self) -> Mode {
        self.mode
    }

    /// Releasing early. Dropping does the same thing; this exists so the intent can be
    /// written down at the call site.
    pub fn release(self) {}
}

impl std::os::fd::AsFd for Inhibitor {
    fn as_fd(&self) -> std::os::fd::BorrowedFd<'_> {
        self.fd.as_fd()
    }
}

impl fmt::Debug for Inhibitor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Inhibitor")
            .field("what", &self.what.as_wire())
            .field("who", &self.who)
            .field("why", &self.why)
            .field("mode", &self.mode)
            .field("fd", &self.fd.as_raw_fd())
            .finish()
    }
}

/// One row of `ListInhibitors`, which is what `systemd-inhibit --list` prints.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActiveInhibitor {
    pub what: What,
    pub who: String,
    pub why: String,
    pub mode: Option<Mode>,
    pub uid: u32,
    pub pid: u32,
}

impl ActiveInhibitor {
    pub(crate) fn from_wire(row: (String, String, String, String, u32, u32)) -> Self {
        let (what, who, why, mode, uid, pid) = row;
        Self {
            what: What::parse(&what),
            who,
            why,
            mode: Mode::parse(&mode),
            uid,
            pid,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The two spellings of the lock `Idle.qml` holds on this seat: what the QML asks
    /// for at `Idle.qml:57`, and what logind's `BlockInhibited` reports back.
    #[test]
    fn the_two_spellings_of_the_shells_own_lock_are_one_set() {
        let asked = What::parse("idle:sleep:handle-lid-switch");
        let reported = What::parse("sleep:idle:handle-lid-switch");
        assert_eq!(asked, reported);
        assert_eq!(asked.as_wire(), "sleep:idle:handle-lid-switch");
        assert!(asked.contains(What::IDLE));
        assert!(asked.contains(What::SLEEP | What::HANDLE_LID_SWITCH));
        assert!(!asked.contains(What::SHUTDOWN));
    }

    #[test]
    fn every_name_logind_261_accepts_round_trips() {
        for (what, name) in What::NAMES {
            assert_eq!(What::parse(name), what, "{name}");
            assert_eq!(what.as_wire(), name);
        }
        let all = What::NAMES
            .iter()
            .fold(What::NONE, |set, (what, _)| set | *what);
        assert_eq!(What::parse(&all.as_wire()), all);
    }

    #[test]
    fn junk_and_empty_segments_leave_the_set_alone() {
        assert!(What::parse("").is_empty());
        assert!(What::parse(":::").is_empty());
        assert_eq!(What::parse("sleep::hack:idle"), What::SLEEP | What::IDLE);
        assert!(What::parse("hack").is_empty());
    }

    #[test]
    fn the_three_modes_round_trip_and_nothing_else_parses() {
        for mode in [Mode::Block, Mode::BlockWeak, Mode::Delay] {
            assert_eq!(Mode::parse(mode.as_wire()), Some(mode));
        }
        assert_eq!(Mode::parse("blocked"), None);
    }

    /// A row read off this seat by `busctl call ... ListInhibitors`.
    #[test]
    fn a_listinhibitors_row_decodes_the_way_systemd_inhibit_list_prints_it() {
        let row = ActiveInhibitor::from_wire((
            "sleep:idle:handle-lid-switch".to_owned(),
            "quickshell".to_owned(),
            "Keep system awake".to_owned(),
            "block".to_owned(),
            1000,
            418610,
        ));
        assert_eq!(row.what.as_wire(), "sleep:idle:handle-lid-switch");
        assert_eq!(row.who, "quickshell");
        assert_eq!(row.mode, Some(Mode::Block));
        assert_eq!(row.uid, 1000);
        assert_eq!(row.pid, 418610);
    }
}
