//! The two interfaces every MPRIS player exports, methods only.
//!
//! Every read goes through `org.freedesktop.DBus.Properties`, never through a cached
//! proxy property. `Position` is annotated in the spec as not emitting
//! `PropertiesChanged`, so a cache over it would hand out a value that stopped being true
//! the moment it was stored.

use zvariant::ObjectPath;

/// A player owns a well-known name under this, and nothing else on the bus does.
pub const PREFIX: &str = "org.mpris.MediaPlayer2.";
pub const PATH: &str = "/org/mpris/MediaPlayer2";
pub const ROOT_IFACE: &str = "org.mpris.MediaPlayer2";
pub const PLAYER_IFACE: &str = "org.mpris.MediaPlayer2.Player";

#[zbus::proxy(
    interface = "org.mpris.MediaPlayer2",
    default_path = "/org/mpris/MediaPlayer2"
)]
pub trait MediaPlayer2 {
    fn raise(&self) -> zbus::Result<()>;

    fn quit(&self) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.mpris.MediaPlayer2.Player",
    default_path = "/org/mpris/MediaPlayer2"
)]
pub trait Player {
    fn next(&self) -> zbus::Result<()>;

    fn previous(&self) -> zbus::Result<()>;

    fn pause(&self) -> zbus::Result<()>;

    fn play_pause(&self) -> zbus::Result<()>;

    fn stop(&self) -> zbus::Result<()>;

    fn play(&self) -> zbus::Result<()>;

    /// Relative, in microseconds, and may be negative.
    fn seek(&self, offset: i64) -> zbus::Result<()>;

    /// Absolute, and refuses if `track_id` is no longer the current track. That guard is
    /// the reason the trackid is worth decoding at all.
    fn set_position(&self, track_id: &ObjectPath<'_>, position: i64) -> zbus::Result<()>;

    /// The one signal that carries a position, and the reason this crate needs no timer.
    #[zbus(signal)]
    fn seeked(&self, position: i64) -> zbus::Result<()>;

    #[zbus(property)]
    fn set_volume(&self, volume: f64) -> zbus::Result<()>;

    #[zbus(property)]
    fn set_loop_status(&self, status: &str) -> zbus::Result<()>;

    #[zbus(property)]
    fn set_shuffle(&self, shuffle: bool) -> zbus::Result<()>;

    #[zbus(property)]
    fn set_rate(&self, rate: f64) -> zbus::Result<()>;
}
