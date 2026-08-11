//! `/dev/rfkill` directly, which is the whole of D14's delta.
//!
//! `BluetoothStatus.qml:24-30` forks `rfkill unblock bluetooth` before every power-on
//! because BlueZ answers a `Powered = true` on a soft-blocked adapter with success and
//! then does nothing. The device carries a `uaccess` ACL for the seat user, so the same
//! ioctl-free protocol the `rfkill` binary speaks is open to us: fixed-size
//! `struct rfkill_event` records in, and out.

use std::fs::{File, OpenOptions};
use std::io::{ErrorKind, Read, Write};
use std::os::unix::fs::OpenOptionsExt;

use koompi_service::{Error, Result};
use tokio::io::unix::AsyncFd;
use tokio::io::Interest;

const DEVICE: &str = "/dev/rfkill";
const SYSFS: &str = "/sys/class/rfkill";

/// linux `O_NONBLOCK`
const O_NONBLOCK: i32 = 0o4000;

/// `struct rfkill_event` as the kernel has laid it out since 2.6.31. Later kernels
/// append `hard_block_reasons`, and a short read of the original 8 stays supported.
const EVENT_LEN: usize = 8;

const TYPE_ALL: u8 = 0;
const TYPE_BLUETOOTH: u8 = 2;

const OP_ADD: u8 = 0;
const OP_DEL: u8 = 1;
const OP_CHANGE: u8 = 2;
const OP_CHANGE_ALL: u8 = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RfkillKind {
    All,
    Wlan,
    Bluetooth,
    Uwb,
    Wimax,
    Wwan,
    Gps,
    Fm,
    Nfc,
    Other(u8),
}

impl RfkillKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::All => "all",
            Self::Wlan => "wlan",
            Self::Bluetooth => "bluetooth",
            Self::Uwb => "uwb",
            Self::Wimax => "wimax",
            Self::Wwan => "wwan",
            Self::Gps => "gps",
            Self::Fm => "fm",
            Self::Nfc => "nfc",
            Self::Other(_) => "other",
        }
    }

    fn from_raw(raw: u8) -> Self {
        match raw {
            0 => Self::All,
            1 => Self::Wlan,
            2 => Self::Bluetooth,
            3 => Self::Uwb,
            4 => Self::Wimax,
            5 => Self::Wwan,
            6 => Self::Gps,
            7 => Self::Fm,
            8 => Self::Nfc,
            other => Self::Other(other),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RfkillEntry {
    pub index: u32,
    pub kind: RfkillKind,
    /// `tpacpi_bluetooth_sw`, `hci0`, `phy0`. The event records carry no name, so this
    /// comes from sysfs and is absent if the switch vanished between the two.
    pub name: Option<String>,
    pub soft_blocked: bool,
    /// A physical kill switch. Software cannot clear it, so a consumer has to be able to
    /// say so rather than retry a power-on that will never take.
    pub hard_blocked: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RfkillState {
    pub entries: Vec<RfkillEntry>,
}

impl RfkillState {
    pub fn bluetooth(&self) -> impl Iterator<Item = &RfkillEntry> {
        self.entries
            .iter()
            .filter(|entry| entry.kind == RfkillKind::Bluetooth)
    }

    /// Any bluetooth switch blocking is enough to stop the adapter, which is why
    /// `rfkill unblock bluetooth` clears the type rather than one index.
    pub fn soft_blocked(&self) -> bool {
        self.bluetooth().any(|entry| entry.soft_blocked)
    }

    pub fn hard_blocked(&self) -> bool {
        self.bluetooth().any(|entry| entry.hard_blocked)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Event {
    index: u32,
    kind: u8,
    op: u8,
    soft: u8,
    hard: u8,
}

impl Event {
    fn decode(bytes: [u8; EVENT_LEN]) -> Self {
        Self {
            index: u32::from_ne_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]),
            kind: bytes[4],
            op: bytes[5],
            soft: bytes[6],
            hard: bytes[7],
        }
    }

    fn encode(self) -> [u8; EVENT_LEN] {
        let index = self.index.to_ne_bytes();
        [
            index[0], index[1], index[2], index[3], self.kind, self.op, self.soft, self.hard,
        ]
    }
}

/// The record `rfkill unblock bluetooth` writes: clear the soft block on every switch of
/// the bluetooth type at once, so a seat with both a platform switch and an adapter
/// switch takes one write rather than one per index.
fn unblock_record() -> [u8; EVENT_LEN] {
    Event {
        index: 0,
        kind: TYPE_BLUETOOTH,
        op: OP_CHANGE_ALL,
        soft: 0,
        hard: 0,
    }
    .encode()
}

fn open(write: bool) -> std::io::Result<File> {
    OpenOptions::new()
        .read(true)
        .write(write)
        .custom_flags(O_NONBLOCK)
        .open(DEVICE)
}

/// A fd of its own rather than a share of the reader's: the reader parks on
/// `readable()` for the life of the service and must never gate a power-on behind it.
pub fn unblock_bluetooth() -> Result<()> {
    let mut file = open(true).map_err(|_| Error::Unavailable(DEVICE.into()))?;
    file.write_all(&unblock_record())?;
    Ok(())
}

/// Follows the device. Opening it replays one `ADD` per existing switch, so the initial
/// state and every later change arrive through the same records and nothing polls.
pub struct Reader {
    fd: AsyncFd<File>,
    state: RfkillState,
}

impl Reader {
    pub fn open() -> Result<Self> {
        let file = open(false).map_err(|_| Error::Unavailable(DEVICE.into()))?;
        let fd = AsyncFd::with_interest(file, Interest::READABLE)?;
        let mut reader = Self {
            fd,
            state: RfkillState::default(),
        };
        reader.drain()?;
        Ok(reader)
    }

    pub fn state(&self) -> &RfkillState {
        &self.state
    }

    /// Resolves once at least one record has landed and every record queued behind it
    /// has been applied.
    pub async fn changed(&mut self) -> Result<()> {
        loop {
            let mut guard = self.fd.readable_mut().await?;
            match guard.try_io(|inner| read_record(inner.get_mut())) {
                Ok(Ok(Some(event))) => {
                    apply(&mut self.state, event);
                    self.drain()?;
                    return Ok(());
                }
                Ok(Ok(None)) => return Err(Error::Protocol("/dev/rfkill closed".into())),
                Ok(Err(error)) => return Err(error.into()),
                Err(_would_block) => continue,
            }
        }
    }

    fn drain(&mut self) -> Result<()> {
        while let Some(event) = read_record(self.fd.get_mut())? {
            apply(&mut self.state, event);
        }
        Ok(())
    }
}

fn read_record(file: &mut File) -> std::io::Result<Option<Event>> {
    let mut bytes = [0u8; EVENT_LEN];
    match file.read(&mut bytes) {
        Ok(0) => Ok(None),
        Ok(EVENT_LEN) => Ok(Some(Event::decode(bytes))),
        // A kernel newer than the struct we asked for still writes whole records; a
        // partial one means the layout moved under us, not a short read to retry.
        Ok(read) => Err(std::io::Error::new(
            ErrorKind::InvalidData,
            format!("rfkill record of {read} bytes"),
        )),
        Err(error) if error.kind() == ErrorKind::WouldBlock => Ok(None),
        Err(error) => Err(error),
    }
}

fn apply(state: &mut RfkillState, event: Event) {
    match event.op {
        OP_DEL => state.entries.retain(|entry| entry.index != event.index),
        OP_ADD | OP_CHANGE => {
            let soft = event.soft != 0;
            let hard = event.hard != 0;
            match state
                .entries
                .iter_mut()
                .find(|entry| entry.index == event.index)
            {
                Some(entry) => {
                    entry.kind = RfkillKind::from_raw(event.kind);
                    entry.soft_blocked = soft;
                    entry.hard_blocked = hard;
                }
                None => {
                    state.entries.push(RfkillEntry {
                        index: event.index,
                        kind: RfkillKind::from_raw(event.kind),
                        name: switch_name(event.index),
                        soft_blocked: soft,
                        hard_blocked: hard,
                    });
                    state.entries.sort_by_key(|entry| entry.index);
                }
            }
        }
        OP_CHANGE_ALL => {
            let kind = RfkillKind::from_raw(event.kind);
            for entry in &mut state.entries {
                if event.kind == TYPE_ALL || entry.kind == kind {
                    entry.soft_blocked = event.soft != 0;
                }
            }
        }
        _ => {}
    }
}

fn switch_name(index: u32) -> Option<String> {
    std::fs::read_to_string(format!("{SYSFS}/rfkill{index}/name"))
        .ok()
        .map(|name| name.trim().to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn add(index: u32, kind: u8, soft: u8, hard: u8) -> Event {
        Event {
            index,
            kind,
            op: OP_ADD,
            soft,
            hard,
        }
    }

    /// This seat's three switches, in the order opening the device replays them.
    fn seat() -> RfkillState {
        let mut state = RfkillState::default();
        apply(&mut state, add(0, TYPE_BLUETOOTH, 0, 0));
        apply(&mut state, add(1, TYPE_BLUETOOTH, 0, 0));
        apply(&mut state, add(2, 1, 0, 0));
        state
    }

    #[test]
    fn a_record_survives_the_round_trip_through_its_bytes() {
        let event = Event {
            index: 7,
            kind: TYPE_BLUETOOTH,
            op: OP_CHANGE,
            soft: 1,
            hard: 0,
        };
        assert_eq!(Event::decode(event.encode()), event);
    }

    /// `strace rfkill unblock bluetooth` writes exactly these eight bytes. The whole
    /// point of D14 is that this record replaces that fork, so its wire form is the
    /// thing worth pinning.
    #[test]
    fn the_unblock_record_is_the_one_the_rfkill_binary_writes() {
        let record = unblock_record();
        let event = Event::decode(record);

        assert_eq!(event.index, 0);
        assert_eq!(event.kind, TYPE_BLUETOOTH);
        assert_eq!(event.op, OP_CHANGE_ALL);
        assert_eq!(event.soft, 0);
        assert_eq!(record.len(), 8);
    }

    #[test]
    fn opening_the_device_replays_one_add_per_switch() {
        let state = seat();

        assert_eq!(state.entries.len(), 3);
        assert_eq!(state.bluetooth().count(), 2);
        assert!(!state.soft_blocked());
        assert!(!state.hard_blocked());
    }

    #[test]
    fn a_change_moves_one_index_and_a_change_all_moves_the_whole_type() {
        let mut state = seat();

        apply(
            &mut state,
            Event {
                index: 1,
                kind: TYPE_BLUETOOTH,
                op: OP_CHANGE,
                soft: 1,
                hard: 0,
            },
        );
        assert!(state.soft_blocked());
        assert!(!state.entries[0].soft_blocked);

        apply(&mut state, Event::decode(unblock_record()));
        assert!(!state.soft_blocked());
        // wifi is a different type and the unblock must not have touched it
        assert!(!state.entries[2].soft_blocked);
    }

    /// A hard block is the physical switch, so `CHANGE_ALL` with `soft = 0` leaves it
    /// standing and the adapter stays unreachable.
    #[test]
    fn an_unblock_cannot_clear_a_hard_block() {
        let mut state = RfkillState::default();
        apply(&mut state, add(1, TYPE_BLUETOOTH, 1, 1));

        apply(&mut state, Event::decode(unblock_record()));

        assert!(!state.soft_blocked());
        assert!(state.hard_blocked());
    }

    #[test]
    fn a_removed_switch_leaves_the_list() {
        let mut state = seat();

        apply(
            &mut state,
            Event {
                index: 1,
                kind: TYPE_BLUETOOTH,
                op: OP_DEL,
                soft: 0,
                hard: 0,
            },
        );

        assert_eq!(state.entries.len(), 2);
        assert!(state.entries.iter().all(|entry| entry.index != 1));
    }
}
