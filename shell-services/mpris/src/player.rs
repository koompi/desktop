//! One player, as plain data, plus the cursor that makes polling `Position` unnecessary.

use std::time::Instant;

use crate::metadata::{Metadata, Props};
use crate::proxy::PREFIX;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackStatus {
    Playing,
    Paused,
    Stopped,
}

impl PlaybackStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Playing => "Playing",
            Self::Paused => "Paused",
            Self::Stopped => "Stopped",
        }
    }

    pub fn is_playing(&self) -> bool {
        *self == Self::Playing
    }
}

impl From<&str> for PlaybackStatus {
    /// Anything unrecognised is stopped. A player that answers nonsense is not playing.
    fn from(raw: &str) -> Self {
        match raw {
            "Playing" => Self::Playing,
            "Paused" => Self::Paused,
            _ => Self::Stopped,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LoopStatus {
    None,
    Track,
    Playlist,
}

impl LoopStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::None => "None",
            Self::Track => "Track",
            Self::Playlist => "Playlist",
        }
    }
}

impl From<&str> for LoopStatus {
    fn from(raw: &str) -> Self {
        match raw {
            "Track" => Self::Track,
            "Playlist" => Self::Playlist,
            _ => Self::None,
        }
    }
}

/// Where playback was the last time the bus said so, and when that was.
///
/// `Position` is the one MPRIS property the spec exempts from `PropertiesChanged`, which
/// is why `MprisController.qml:174-183` runs a three-second timer. It is also derivable:
/// between a status change and the next one, position moves at `rate` and nothing else
/// moves it except `Seeked`, which is a signal. So the anchor is re-read on the events
/// that invalidate it and interpolated in between, and no timer is involved.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PositionCursor {
    /// Microseconds, as the bus reported it.
    pub position_us: i64,
    /// The instant `position_us` was read, so a consumer can interpolate for itself.
    pub read_at: Instant,
    /// 1.0 is normal speed; the cursor advances at this multiple of wall clock.
    pub rate: f64,
    /// False while paused or stopped, when the anchor stays true indefinitely.
    pub advancing: bool,
}

impl PositionCursor {
    pub fn new(position_us: i64, rate: f64, advancing: bool) -> Self {
        Self {
            position_us,
            read_at: Instant::now(),
            rate,
            advancing,
        }
    }

    /// The position at `now`, with no clamp. See [`Player::position_now`] for the form a
    /// consumer usually wants.
    pub fn at(&self, now: Instant) -> i64 {
        if !self.advancing || now <= self.read_at {
            return self.position_us;
        }
        let elapsed = now.duration_since(self.read_at).as_micros() as f64;
        let moved = elapsed * if self.rate.is_finite() { self.rate } else { 1.0 };
        self.position_us.saturating_add(moved as i64)
    }

    /// How far past a known length the cursor has run. Zero for everything honest; it
    /// grows only when a player claims to be playing and is not.
    pub fn overrun(&self, now: Instant, length_us: Option<i64>) -> i64 {
        match length_us {
            Some(length) if length > 0 => (self.at(now) - length).max(0),
            _ => 0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Capabilities {
    pub go_next: bool,
    pub go_previous: bool,
    pub play: bool,
    pub pause: bool,
    pub seek: bool,
    pub control: bool,
}

/// Why a player is not a candidate for the active slot, reproducing the filter at
/// `MprisController.qml:35-46`. It stays in the list either way: whether a duplicate is
/// hidden is a consumer's decision, and this is the fact the decision is made from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Shadowed {
    /// A browser's own bus, while plasma-browser-integration is on the bus carrying the
    /// same playback with art and an artist the browser's bus does not have.
    PlasmaIntegration,
    /// playerctld republishes another player's bus verbatim.
    Playerctld,
    /// mpd exports one bus per instance plus a bare one; the instance buses are copies.
    MpdInstance,
}

impl Shadowed {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::PlasmaIntegration => "plasma-browser-integration owns this playback",
            Self::Playerctld => "playerctld mirrors another player",
            Self::MpdInstance => "a per-instance mpd bus",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Player {
    /// The well-known name, `org.mpris.MediaPlayer2.something`.
    pub bus_name: String,
    /// The unique name behind it, which is what a signal from this player carries.
    pub owner: String,
    pub identity: String,
    pub desktop_entry: String,
    pub can_quit: bool,
    pub can_raise: bool,
    pub playback_status: PlaybackStatus,
    pub metadata: Metadata,
    /// `None` where the player does not export it, which is different from 0.0.
    pub volume: Option<f64>,
    pub loop_status: Option<LoopStatus>,
    pub shuffle: Option<bool>,
    pub rate: f64,
    pub minimum_rate: f64,
    pub maximum_rate: f64,
    pub capabilities: Capabilities,
    pub position: PositionCursor,
    /// When this player last said anything about its playback. The fallback half of the
    /// priority rule at `MprisController.qml:20-32` orders on it.
    pub last_active: Instant,
    pub shadowed: Option<Shadowed>,
}

impl Player {
    /// The suffix after `org.mpris.MediaPlayer2.`, which is what `playerctl -p` takes.
    pub fn suffix(&self) -> &str {
        self.bus_name.strip_prefix(PREFIX).unwrap_or(&self.bus_name)
    }

    pub fn is_playing(&self) -> bool {
        self.playback_status.is_playing()
    }

    /// Interpolated to now and held inside the track, so a player that keeps claiming to
    /// play past the end reads as sitting at the end rather than running off into
    /// numbers no track has.
    pub fn position_now(&self) -> i64 {
        self.position_at(Instant::now())
    }

    pub fn position_at(&self, now: Instant) -> i64 {
        let position = self.position.at(now).max(0);
        match self.metadata.length_us {
            Some(length) if length > 0 => position.min(length),
            _ => position,
        }
    }

    /// True when the player says it is playing and the cursor has run past the end of the
    /// track by more than `slack`.
    ///
    /// This is what `MprisController.qml:131-144` uses a `playerctl` subprocess and a
    /// three-second timer to find out. Reaching the end while still Playing is either a
    /// player that stopped telling the truth or a gapless transition that has not landed
    /// yet, and `slack` separates the two.
    pub fn overran(&self, now: Instant, slack_us: i64) -> bool {
        self.is_playing() && self.position.overrun(now, self.metadata.length_us) > slack_us
    }

    /// Root and Player properties in one, both read with `GetAll`.
    pub(crate) fn from_props(
        bus_name: String,
        owner: String,
        root: &Props,
        player: &Props,
        shadowed: Option<Shadowed>,
    ) -> Self {
        let status = PlaybackStatus::from(props::text(player, "PlaybackStatus").as_deref().unwrap_or(""));
        let rate = props::real(player, "Rate").filter(|r| r.is_finite() && *r > 0.0).unwrap_or(1.0);
        Self {
            identity: props::text(root, "Identity").unwrap_or_else(|| {
                bus_name.strip_prefix(PREFIX).unwrap_or(&bus_name).to_owned()
            }),
            desktop_entry: props::text(root, "DesktopEntry").unwrap_or_default(),
            can_quit: props::boolean(root, "CanQuit").unwrap_or(false),
            can_raise: props::boolean(root, "CanRaise").unwrap_or(false),
            playback_status: status,
            metadata: props::map(player, "Metadata")
                .map(|inner| Metadata::from_props(&inner))
                .unwrap_or_default(),
            volume: props::real(player, "Volume").filter(|v| v.is_finite()),
            loop_status: props::text(player, "LoopStatus").map(|raw| LoopStatus::from(raw.as_str())),
            shuffle: props::boolean(player, "Shuffle"),
            rate,
            minimum_rate: props::real(player, "MinimumRate").unwrap_or(1.0),
            maximum_rate: props::real(player, "MaximumRate").unwrap_or(1.0),
            capabilities: Capabilities {
                go_next: props::boolean(player, "CanGoNext").unwrap_or(false),
                go_previous: props::boolean(player, "CanGoPrevious").unwrap_or(false),
                play: props::boolean(player, "CanPlay").unwrap_or(false),
                pause: props::boolean(player, "CanPause").unwrap_or(false),
                seek: props::boolean(player, "CanSeek").unwrap_or(false),
                control: props::boolean(player, "CanControl").unwrap_or(false),
            },
            position: PositionCursor::new(
                props::integer(player, "Position").unwrap_or(0),
                rate,
                status.is_playing(),
            ),
            last_active: Instant::now(),
            bus_name,
            owner,
            shadowed,
        }
    }
}

/// Only the shapes the two MPRIS interfaces use, read the same lenient way the metadata
/// map is: a mistyped property falls back rather than failing the player.
pub(crate) mod props {
    use std::collections::HashMap;

    use zvariant::{OwnedValue, Value};

    use crate::metadata::Props;

    fn unbox<'d, 'v>(value: &'d Value<'v>) -> &'d Value<'v> {
        match value {
            Value::Value(inner) => inner,
            other => other,
        }
    }

    pub fn text(props: &Props, key: &str) -> Option<String> {
        match unbox(props.get(key)?) {
            Value::Str(s) => Some(s.to_string()),
            _ => None,
        }
    }

    pub fn boolean(props: &Props, key: &str) -> Option<bool> {
        match unbox(props.get(key)?) {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn real(props: &Props, key: &str) -> Option<f64> {
        match unbox(props.get(key)?) {
            Value::F64(f) => Some(*f),
            Value::I64(n) => Some(*n as f64),
            Value::I32(n) => Some(*n as f64),
            Value::U32(n) => Some(*n as f64),
            _ => None,
        }
    }

    pub fn integer(props: &Props, key: &str) -> Option<i64> {
        number(props.get(key)?)
    }

    /// `Position` arrives on its own, out of any map, so the decode has to work on a
    /// bare value too.
    pub fn number(value: &Value<'_>) -> Option<i64> {
        match unbox(value) {
            Value::I64(n) => Some(*n),
            Value::U64(n) => i64::try_from(*n).ok(),
            Value::I32(n) => Some(*n as i64),
            Value::U32(n) => Some(*n as i64),
            Value::F64(f) => f.is_finite().then_some(*f as i64),
            _ => None,
        }
    }

    pub fn map(props: &Props, key: &str) -> Option<Props> {
        let Value::Dict(dict) = unbox(props.get(key)?) else {
            return None;
        };
        let pairs: HashMap<String, OwnedValue> = dict
            .iter()
            .filter_map(|(k, v)| {
                let Value::Str(k) = unbox(k) else { return None };
                Some((k.to_string(), OwnedValue::try_from(v.try_clone().ok()?).ok()?))
            })
            .collect();
        Some(pairs)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn cursor(position_us: i64, advancing: bool) -> PositionCursor {
        PositionCursor {
            position_us,
            read_at: Instant::now(),
            rate: 1.0,
            advancing,
        }
    }

    #[test]
    fn a_playing_cursor_advances_with_the_clock_and_a_paused_one_does_not() {
        let playing = cursor(10_000_000, true);
        let paused = cursor(10_000_000, false);
        let later = playing.read_at + Duration::from_secs(4);

        assert_eq!(playing.at(later), 14_000_000);
        assert_eq!(paused.at(later), 10_000_000);
        // A consumer asking before the anchor was taken gets the anchor, not a rewind.
        assert_eq!(playing.at(playing.read_at - Duration::from_secs(1)), 10_000_000);
    }

    #[test]
    fn rate_scales_the_interpolation() {
        let mut fast = cursor(0, true);
        fast.rate = 2.0;
        assert_eq!(fast.at(fast.read_at + Duration::from_secs(3)), 6_000_000);

        let mut broken = cursor(0, true);
        broken.rate = f64::NAN;
        assert_eq!(broken.at(broken.read_at + Duration::from_secs(3)), 3_000_000);
    }

    #[test]
    fn overrun_is_zero_for_a_track_still_inside_its_length() {
        let playing = cursor(10_000_000, true);
        let now = playing.read_at + Duration::from_secs(4);

        assert_eq!(playing.overrun(now, Some(30_000_000)), 0);
        assert_eq!(playing.overrun(now, Some(12_000_000)), 2_000_000);
        // A stream with no length can never overrun one.
        assert_eq!(playing.overrun(now, None), 0);
        assert_eq!(playing.overrun(now, Some(-1)), 0);
    }
}
