//! D14 bluetooth: org.bluez, with the rfkill unblock kept because BlueZ fails silently
//! on a soft block.
//!
//! The delta over `BluetoothStatus.qml` is that the unblock stops being a fork of the
//! `rfkill` binary and becomes a write to `/dev/rfkill`, which also gives the shell the
//! one thing the fork never returned: whether the block is soft or a hardware switch.
//!
//! Ordering the device list is presentation and stays with the consumer. This crate
//! publishes the fields to order by.

mod model;
mod objects;
mod props;
mod proxy;
mod rfkill;
mod service;

pub use model::{Adapter, Device, PowerState};
pub use rfkill::{RfkillEntry, RfkillKind, RfkillState};
pub use service::{BluetoothService, BluetoothState};
