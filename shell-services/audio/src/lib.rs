//! D13 audio, the Rust half: `audiod` owns the libpipewire mainloop in zig, this crate
//! only speaks NDJSON to it so consumers never learn which language answered.
//!
//! `audiod/PROTOCOL.md` is what this implements. Nothing here is derived from the zig
//! source, so a second implementation of either side stays possible.

mod model;
mod proto;
mod service;

pub use model::{AudioState, DaemonStatus, Node};
pub use proto::{
    Command, DaemonError, Hello, Message, Reply, Unavailable, MAX_VOLUME, PROTOCOL_VERSION,
};
pub use service::{resolve_binary, AudioService, BINARY_ENV};
