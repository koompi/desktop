//! D08 mpris: native `PropertiesChanged` retires both the three-second poll and the
//! `playerctl` probe the QML needs to unstick plasma-browser-integration.
//!
//! `MprisController.qml` gets its players from a Quickshell builtin and then bolts two
//! things on top of it. A `Process` at `:147-172` runs `playerctl -p <player> position`,
//! and a `Timer` at `:174-183` fires it every three seconds for as long as
//! plasma-browser-integration is the active player and claims to be playing. Both exist
//! because the builtin extrapolates position for anything Playing and therefore cannot
//! see that player's position freeze.
//!
//! Neither is here. Position is anchored from the bus on the three events that can
//! invalidate it, a status change, a rate change or a new track, plus the `Seeked` signal
//! the spec provides for exactly this, and interpolated in between. See
//! [`PositionCursor`]. Nothing in this crate runs on a schedule; the only wait is the
//! retry after a player claims its bus name before exporting the object behind it.
//!
//! The freeze is still detectable, and without a subprocess: a player whose interpolated
//! position has run past `mpris:length` while still claiming to play is lying, and
//! [`Player::overran`] says so. A consumer that wants the player's own number rather than
//! the interpolated one calls [`MprisService::read_position`], which is one `Get` when
//! someone asks instead of one every three seconds forever.
//!
//! Art is a URL and stays a URL, whether it is `file://`, `http://` or a `data:` blob.
//! Fetching, decoding and drawing it are all somebody else's job, and none of the three
//! can be done without a dependency this crate refuses.
//!
//! ```no_run
//! use koompi_mpris::{MprisConfig, MprisService};
//! use koompi_service::Service;
//!
//! # async fn run() -> koompi_service::Result<()> {
//! let mpris = MprisService::connect(MprisConfig::default()).await?;
//! if let Some(player) = mpris.state().active_player() {
//!     println!(
//!         "{} - {} at {} us ({})",
//!         player.identity,
//!         player.metadata.title.as_deref().unwrap_or(""),
//!         player.position_now(),
//!         mpris.state().reason.as_str(),
//!     );
//! }
//! # Ok(())
//! # }
//! ```

pub mod metadata;
pub mod player;
pub mod priority;
pub mod proxy;
pub mod service;

pub use metadata::{decoded_keys, track_moved, Metadata};
pub use player::{Capabilities, LoopStatus, PlaybackStatus, Player, PositionCursor, Shadowed};
pub use priority::{choose, shadow_of, ChoiceReason};
pub use service::{MprisConfig, MprisEvent, MprisService, MprisState, OVERRUN_SLACK};
