//! `Metadata` is `a{sv}` and players disagree about nearly every key in it.
//!
//! The rule throughout: a key whose type is not what the spec says drops **that key**,
//! never the track. A player that sends `mpris:length` as a string still has a title, and
//! a consumer that gets no track at all cannot draw anything.

use std::collections::HashMap;

use zvariant::{OwnedValue, Value};

pub type Props = HashMap<String, OwnedValue>;

/// Art is forwarded exactly as received: `file://`, `http://` or a `data:` URI. Fetching
/// it needs an HTTP client, decoding it needs an image crate, and drawing it needs a
/// toolkit. This crate has none of the three, on purpose. Same rule the tray follows for
/// its pixmaps.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Metadata {
    pub track_id: Option<String>,
    /// Microseconds. `mpris:length` is `x` in the spec and `t` in several players.
    pub length_us: Option<i64>,
    pub art_url: Option<String>,
    pub title: Option<String>,
    /// `xesam:artist` is `as`, but a bare `s` is common enough to be normal.
    pub artists: Vec<String>,
    pub album: Option<String>,
    pub url: Option<String>,
    /// Every key that did not land in a field above, sorted: keys this crate has no
    /// place for, and keys whose type was wrong. Kept so a player that invents something
    /// can be seen rather than silently ignored.
    pub undecoded: Vec<String>,
}

const DECODED: [&str; 7] = [
    "mpris:trackid",
    "mpris:length",
    "mpris:artUrl",
    "xesam:title",
    "xesam:artist",
    "xesam:album",
    "xesam:url",
];

impl Metadata {
    pub fn from_props(props: &Props) -> Self {
        let mut metadata = Self {
            track_id: prop(props, "mpris:trackid").and_then(path_or_text),
            length_us: prop(props, "mpris:length")
                .and_then(integer)
                .filter(|length| *length >= 0),
            art_url: prop(props, "mpris:artUrl").and_then(text),
            title: prop(props, "xesam:title").and_then(text),
            artists: prop(props, "xesam:artist").map(strings).unwrap_or_default(),
            album: prop(props, "xesam:album").and_then(text),
            url: prop(props, "xesam:url").and_then(text),
            undecoded: Vec::new(),
        };
        metadata.undecoded = props
            .keys()
            .filter(|key| !metadata.decoded(key))
            .cloned()
            .collect();
        metadata.undecoded.sort();
        metadata
    }

    /// True once a player has said anything about the track. `PlaybackStatus` alone is
    /// not a track: browsers leave a stopped player holding an empty metadata map.
    pub fn is_empty(&self) -> bool {
        self.track_id.is_none()
            && self.title.is_none()
            && self.artists.is_empty()
            && self.album.is_none()
            && self.url.is_none()
    }

    /// `xesam:artist` joined the way a single line wants it. Nothing here decides what a
    /// consumer shows when it is absent; an empty string is empty, not "Unknown Artist".
    pub fn artist(&self) -> String {
        self.artists.join(", ")
    }

    fn decoded(&self, key: &str) -> bool {
        match key {
            "mpris:trackid" => self.track_id.is_some(),
            "mpris:length" => self.length_us.is_some(),
            "mpris:artUrl" => self.art_url.is_some(),
            "xesam:title" => self.title.is_some(),
            "xesam:artist" => !self.artists.is_empty(),
            "xesam:album" => self.album.is_some(),
            "xesam:url" => self.url.is_some(),
            _ => false,
        }
    }
}

/// Which of the seven keys this crate reads at all, for anything reporting on coverage.
pub fn decoded_keys() -> &'static [&'static str] {
    &DECODED
}

/// Whether these two maps describe different tracks, which is the question that decides
/// whether the position anchor is still worth anything.
///
/// A changed `mpris:artUrl` on its own is not a new track. `MprisController.qml:96-97`
/// found that out the hard way: cantata sends the cover before the track info it belongs
/// to, so treating art as a track change turns one track into two.
pub fn track_moved(before: &Metadata, after: &Metadata) -> bool {
    if before.track_id.is_some() || after.track_id.is_some() {
        return before.track_id != after.track_id;
    }
    before.title != after.title || before.url != after.url
}

/// A `v` inside a `v`: some players box their metadata values twice.
fn unbox<'d, 'v>(value: &'d Value<'v>) -> &'d Value<'v> {
    match value {
        Value::Value(inner) => inner,
        other => other,
    }
}

fn prop<'p>(props: &'p Props, key: &str) -> Option<&'p Value<'p>> {
    props.get(key).map(|owned| unbox(owned))
}

fn text(value: &Value<'_>) -> Option<String> {
    match value {
        Value::Str(s) => Some(s.to_string()).filter(|s| !s.is_empty()),
        _ => None,
    }
}

/// `mpris:trackid` is `o` in the spec. Chromium and several others send `s`, and one of
/// those strings is not even a valid path, so it is kept as text and only turned back
/// into an `ObjectPath` where `SetPosition` demands one.
fn path_or_text(value: &Value<'_>) -> Option<String> {
    match value {
        Value::ObjectPath(path) => Some(path.to_string()),
        Value::Str(s) => Some(s.to_string()).filter(|s| !s.is_empty()),
        _ => None,
    }
}

fn integer(value: &Value<'_>) -> Option<i64> {
    match value {
        Value::I64(n) => Some(*n),
        Value::U64(n) => i64::try_from(*n).ok(),
        Value::I32(n) => Some(*n as i64),
        Value::U32(n) => Some(*n as i64),
        Value::I16(n) => Some(*n as i64),
        Value::U16(n) => Some(*n as i64),
        Value::U8(n) => Some(*n as i64),
        Value::F64(n) => n.is_finite().then_some(*n as i64),
        _ => None,
    }
}

fn strings(value: &Value<'_>) -> Vec<String> {
    match value {
        Value::Array(array) => array
            .iter()
            .filter_map(|item| text(unbox(item)))
            .collect(),
        Value::Str(_) => text(value).into_iter().collect(),
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(crate) fn props(pairs: Vec<(&str, Value<'static>)>) -> Props {
        pairs
            .into_iter()
            .map(|(k, v)| (k.to_owned(), OwnedValue::try_from(v).unwrap()))
            .collect()
    }

    fn path(literal: &'static str) -> Value<'static> {
        Value::ObjectPath(zvariant::ObjectPath::try_from(literal).unwrap())
    }

    /// Captured verbatim from this machine:
    ///
    /// ```text
    /// $ busctl --user get-property org.mpris.MediaPlayer2.chromium.instance543474 \
    ///     /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata
    /// a{sv} 6 "mpris:artUrl" s "file:///home/userx/.tmp/.org.chromium.Chromium.tEhuvo"
    ///   "mpris:length" x 180000000
    ///   "mpris:trackid" o "/org/chromium/MediaPlayer2/TrackList/TrackC2C24FC673F82F535A414B1F94CCDFBB"
    ///   "xesam:album" s "" "xesam:artist" as 1 "" "xesam:title" s "J08 test player"
    /// ```
    ///
    /// A tab with no `MediaSession` metadata: the album and the one artist are present as
    /// empty strings, and the title is the page title. That is what
    /// `MprisController.qml:22-24` means by the browser's own bus carrying no art and no
    /// artist, and the empty strings have to read as absence or every card draws a blank
    /// line where the artist goes.
    #[test]
    fn a_chromium_tab_with_no_media_session_has_empty_strings_where_a_track_would_be() {
        let metadata = Metadata::from_props(&props(vec![
            (
                "mpris:artUrl",
                "file:///home/userx/.tmp/.org.chromium.Chromium.tEhuvo".into(),
            ),
            ("mpris:length", 180_000_000i64.into()),
            (
                "mpris:trackid",
                path("/org/chromium/MediaPlayer2/TrackList/TrackC2C24FC673F82F535A414B1F94CCDFBB"),
            ),
            ("xesam:album", "".into()),
            ("xesam:artist", Value::from(vec![String::new()])),
            ("xesam:title", "J08 test player".into()),
        ]));

        assert_eq!(
            metadata.track_id.as_deref(),
            Some("/org/chromium/MediaPlayer2/TrackList/TrackC2C24FC673F82F535A414B1F94CCDFBB")
        );
        assert_eq!(metadata.length_us, Some(180_000_000));
        assert_eq!(metadata.title.as_deref(), Some("J08 test player"));
        assert!(metadata.artists.is_empty());
        assert_eq!(metadata.album, None);
        assert_eq!(metadata.undecoded, ["xesam:album", "xesam:artist"]);
        assert!(!metadata.is_empty());
    }

    /// Captured verbatim from this machine, the same tab through the other bus:
    ///
    /// ```text
    /// $ busctl --user get-property org.mpris.MediaPlayer2.plasma-browser-integration \
    ///     /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Metadata
    /// a{sv} 9 "kde:mediaSrc" s "http://127.0.0.1:8099/track.mp3" "kde:pid" i 543474
    ///   "mpris:artUrl" s "http://127.0.0.1:8099/art.png" "mpris:length" x 180000000
    ///   "mpris:trackid" o "/org/kde/plasma/browser_integration/1337"
    ///   "xesam:album" s "Standing Wave" "xesam:artist" as 1 "The Interference"
    ///   "xesam:title" s "Solder and Static" "xesam:url" s "http://127.0.0.1:8099/player.html"
    /// ```
    ///
    /// Two keys the spec has never heard of, and an art URL that is an origin rather than
    /// a file. Both survive: the keys are reported, and the URL is forwarded untouched.
    #[test]
    fn plasma_browser_integration_decodes_whole_and_reports_its_kde_keys() {
        let metadata = Metadata::from_props(&props(vec![
            ("kde:mediaSrc", "http://127.0.0.1:8099/track.mp3".into()),
            ("kde:pid", 543474i32.into()),
            ("mpris:artUrl", "http://127.0.0.1:8099/art.png".into()),
            ("mpris:length", 180_000_000i64.into()),
            ("mpris:trackid", path("/org/kde/plasma/browser_integration/1337")),
            ("xesam:album", "Standing Wave".into()),
            ("xesam:artist", Value::from(vec!["The Interference".to_owned()])),
            ("xesam:title", "Solder and Static".into()),
            ("xesam:url", "http://127.0.0.1:8099/player.html".into()),
        ]));

        assert_eq!(
            metadata.track_id.as_deref(),
            Some("/org/kde/plasma/browser_integration/1337")
        );
        assert_eq!(metadata.length_us, Some(180_000_000));
        // Forwarded byte for byte: no fetch, no decode, no rewrite to a cache path.
        assert_eq!(
            metadata.art_url.as_deref(),
            Some("http://127.0.0.1:8099/art.png")
        );
        assert_eq!(metadata.title.as_deref(), Some("Solder and Static"));
        assert_eq!(metadata.artist(), "The Interference");
        assert_eq!(metadata.album.as_deref(), Some("Standing Wave"));
        assert_eq!(
            metadata.url.as_deref(),
            Some("http://127.0.0.1:8099/player.html")
        );
        assert_eq!(metadata.undecoded, ["kde:mediaSrc", "kde:pid"]);
    }

    /// The spec says `o` and both players on this machine send `o`, but a `s` trackid is
    /// common enough elsewhere that dropping it would lose `SetPosition`'s guard.
    #[test]
    fn a_trackid_sent_as_a_string_is_kept() {
        let metadata = Metadata::from_props(&props(vec![(
            "mpris:trackid",
            "/org/mpd/Track/7".into(),
        )]));
        assert_eq!(metadata.track_id.as_deref(), Some("/org/mpd/Track/7"));
        assert!(metadata.undecoded.is_empty());
    }

    #[test]
    fn a_bare_string_artist_reads_as_one_artist() {
        let bare = Metadata::from_props(&props(vec![(
            "xesam:artist",
            "The Interference".into(),
        )]));
        assert_eq!(bare.artists, ["The Interference"]);
        assert_eq!(bare.artist(), "The Interference");

        let many = Metadata::from_props(&props(vec![(
            "xesam:artist",
            Value::from(vec!["A".to_owned(), "B".to_owned()]),
        )]));
        assert_eq!(many.artist(), "A, B");
    }

    #[test]
    fn a_key_with_the_wrong_type_drops_that_key_and_keeps_the_track() {
        let metadata = Metadata::from_props(&props(vec![
            ("xesam:title", "Kept".into()),
            ("mpris:length", "213000000".into()),
            ("mpris:artUrl", 42i32.into()),
            ("mpris:trackid", Value::from(vec![1i32])),
            ("xesam:album", Value::Bool(true)),
        ]));

        assert_eq!(metadata.title.as_deref(), Some("Kept"));
        assert_eq!(metadata.length_us, None);
        assert_eq!(metadata.art_url, None);
        assert_eq!(metadata.track_id, None);
        assert_eq!(metadata.album, None);
        assert_eq!(
            metadata.undecoded,
            ["mpris:artUrl", "mpris:length", "mpris:trackid", "xesam:album"]
        );
        assert!(!metadata.is_empty());
    }

    #[test]
    fn a_length_that_arrived_as_t_or_negative_is_handled_not_wrapped() {
        let unsigned = Metadata::from_props(&props(vec![("mpris:length", 213_000_000u64.into())]));
        assert_eq!(unsigned.length_us, Some(213_000_000));

        // Some players report -1 for a live stream. That is not a duration.
        let live = Metadata::from_props(&props(vec![("mpris:length", (-1i64).into())]));
        assert_eq!(live.length_us, None);

        let huge = Metadata::from_props(&props(vec![("mpris:length", u64::MAX.into())]));
        assert_eq!(huge.length_us, None);
    }

    #[test]
    fn an_empty_map_is_an_empty_track_rather_than_a_track_of_blanks() {
        let metadata = Metadata::from_props(&Props::new());
        assert!(metadata.is_empty());
        assert_eq!(metadata.artist(), "");
        assert!(metadata.undecoded.is_empty());
    }

    #[test]
    fn cover_art_arriving_before_its_track_is_not_a_new_track() {
        let track = Metadata::from_props(&props(vec![
            ("xesam:title", "Ferrite Bloom".into()),
            ("mpris:artUrl", "file:///cache/a.png".into()),
        ]));
        let recovered = Metadata::from_props(&props(vec![
            ("xesam:title", "Ferrite Bloom".into()),
            ("mpris:artUrl", "file:///cache/b.png".into()),
        ]));
        assert!(!track_moved(&track, &recovered));

        let next = Metadata::from_props(&props(vec![("xesam:title", "Standing Wave".into())]));
        assert!(track_moved(&track, &next));
    }

    #[test]
    fn a_track_id_settles_it_wherever_one_exists() {
        let one = Metadata::from_props(&props(vec![
            ("mpris:trackid", path("/Track/1")),
            ("xesam:title", "Same Title".into()),
        ]));
        let two = Metadata::from_props(&props(vec![
            ("mpris:trackid", path("/Track/2")),
            ("xesam:title", "Same Title".into()),
        ]));
        assert!(track_moved(&one, &two));
        assert!(!track_moved(&one, &one.clone()));
        // The id going away is a move too: the player stopped holding that track.
        assert!(track_moved(&one, &Metadata::default()));
    }

    #[test]
    fn keys_outside_the_seven_are_reported_not_dropped_silently() {
        let metadata = Metadata::from_props(&props(vec![
            ("xesam:title", "Kept".into()),
            ("xesam:trackNumber", 3i32.into()),
            ("kde:senderIdentity", "Chromium".into()),
        ]));
        assert_eq!(metadata.undecoded, ["kde:senderIdentity", "xesam:trackNumber"]);
        assert_eq!(decoded_keys().len(), 7);
    }
}
