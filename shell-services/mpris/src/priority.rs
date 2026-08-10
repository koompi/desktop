//! Which of several players the shell is talking about, and why.
//!
//! `MprisController.qml:20-32` reaches the same answer through four bits of mutable state
//! spread over an `Instantiator`, two `Connections` and a property binding: a player
//! becomes tracked when it appears playing, when its playback state changes, or when the
//! tracked one is destroyed. Stated as a rule over the list rather than as a sequence of
//! assignments, that is: prefer the one that is playing, and fall back to the one that
//! most recently said anything.

use crate::player::{Player, Shadowed};
use crate::proxy::PREFIX;

/// Why the active player is the active player. A consumer that draws one card out of
/// three players should be able to say which, without guessing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChoiceReason {
    /// No player on the bus, or every one of them shadowed.
    Nothing,
    /// A consumer asked for this one by name and it is still a candidate.
    Pinned,
    /// The only candidate there was.
    Only,
    /// Playing, where the others are not.
    Playing,
    /// Nothing is playing, so the one that last changed anything wins.
    MostRecentlyActive,
}

impl ChoiceReason {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Nothing => "no candidate",
            Self::Pinned => "pinned by the consumer",
            Self::Only => "the only candidate",
            Self::Playing => "playing",
            Self::MostRecentlyActive => "most recently active",
        }
    }
}

/// Whether this bus is a copy of another one on the same bus, per
/// `MprisController.qml:35-46`. Takes the full set of names because the answer depends on
/// who else is there: a browser's own bus is only a duplicate while
/// plasma-browser-integration is running.
pub fn shadow_of(bus_name: &str, all: &[String]) -> Option<Shadowed> {
    let suffix = bus_name.strip_prefix(PREFIX)?;

    if suffix.starts_with("playerctld") {
        return Some(Shadowed::Playerctld);
    }
    // A bus that ends in `.mpd` without being *the* mpd bus is a per-instance copy.
    if bus_name.ends_with(".mpd") && bus_name != "org.mpris.MediaPlayer2.mpd" {
        return Some(Shadowed::MpdInstance);
    }
    let plasma = all
        .iter()
        .any(|name| name.starts_with("org.mpris.MediaPlayer2.plasma-browser-integration"));
    if plasma && (suffix.starts_with("firefox") || suffix.starts_with("chromium")) {
        return Some(Shadowed::PlasmaIntegration);
    }
    None
}

/// The index of the active player, and the reason.
pub fn choose(players: &[Player], pinned: Option<&str>) -> (Option<usize>, ChoiceReason) {
    let candidates: Vec<usize> = players
        .iter()
        .enumerate()
        .filter(|(_, player)| player.shadowed.is_none())
        .map(|(index, _)| index)
        .collect();

    // Every player on the bus is a shadow of one that has gone. Better to draw the copy
    // than to draw nothing.
    let candidates = if candidates.is_empty() {
        (0..players.len()).collect()
    } else {
        candidates
    };

    if let Some(pinned) = pinned {
        if let Some(&index) = candidates
            .iter()
            .find(|&&index| players[index].bus_name == pinned)
        {
            return (Some(index), ChoiceReason::Pinned);
        }
    }

    let newest = |subset: &mut dyn Iterator<Item = &usize>| -> Option<usize> {
        subset.copied().max_by_key(|&index| players[index].last_active)
    };

    let playing: Vec<usize> = candidates
        .iter()
        .copied()
        .filter(|&index| players[index].is_playing())
        .collect();

    if let Some(index) = newest(&mut playing.iter()) {
        let reason = if candidates.len() == 1 {
            ChoiceReason::Only
        } else {
            ChoiceReason::Playing
        };
        return (Some(index), reason);
    }

    match newest(&mut candidates.iter()) {
        Some(index) if candidates.len() == 1 => (Some(index), ChoiceReason::Only),
        Some(index) => (Some(index), ChoiceReason::MostRecentlyActive),
        None => (None, ChoiceReason::Nothing),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::metadata::Props;
    use crate::player::PlaybackStatus;
    use std::time::{Duration, Instant};

    fn player(suffix: &str, status: PlaybackStatus, age: Duration, all: &[String]) -> Player {
        let bus_name = format!("{PREFIX}{suffix}");
        let mut player = Player::from_props(
            bus_name.clone(),
            ":1.1".into(),
            &Props::new(),
            &Props::new(),
            shadow_of(&bus_name, all),
        );
        player.playback_status = status;
        player.last_active = Instant::now() - age;
        player
    }

    fn names(suffixes: &[&str]) -> Vec<String> {
        suffixes.iter().map(|s| format!("{PREFIX}{s}")).collect()
    }

    #[test]
    fn the_playing_player_wins_over_a_more_recently_touched_paused_one() {
        let all = names(&["vlc", "chromium.instance_1"]);
        let players = vec![
            player("vlc", PlaybackStatus::Playing, Duration::from_secs(60), &all),
            player(
                "chromium.instance_1",
                PlaybackStatus::Paused,
                Duration::from_secs(1),
                &all,
            ),
        ];

        let (index, reason) = choose(&players, None);
        assert_eq!(players[index.unwrap()].suffix(), "vlc");
        assert_eq!(reason, ChoiceReason::Playing);
    }

    #[test]
    fn with_nothing_playing_the_most_recently_active_wins() {
        let all = names(&["vlc", "chromium.instance_1"]);
        let players = vec![
            player("vlc", PlaybackStatus::Paused, Duration::from_secs(60), &all),
            player(
                "chromium.instance_1",
                PlaybackStatus::Stopped,
                Duration::from_secs(1),
                &all,
            ),
        ];

        let (index, reason) = choose(&players, None);
        assert_eq!(players[index.unwrap()].suffix(), "chromium.instance_1");
        assert_eq!(reason, ChoiceReason::MostRecentlyActive);
    }

    #[test]
    fn two_playing_players_are_settled_by_which_spoke_last() {
        let all = names(&["vlc", "mpd"]);
        let players = vec![
            player("vlc", PlaybackStatus::Playing, Duration::from_secs(9), &all),
            player("mpd", PlaybackStatus::Playing, Duration::from_secs(1), &all),
        ];

        let (index, reason) = choose(&players, None);
        assert_eq!(players[index.unwrap()].suffix(), "mpd");
        assert_eq!(reason, ChoiceReason::Playing);
    }

    #[test]
    fn a_pin_holds_until_the_pinned_player_stops_being_a_candidate() {
        let all = names(&["vlc", "mpd"]);
        let players = vec![
            player("vlc", PlaybackStatus::Paused, Duration::from_secs(60), &all),
            player("mpd", PlaybackStatus::Playing, Duration::from_secs(1), &all),
        ];

        let (index, reason) = choose(&players, Some("org.mpris.MediaPlayer2.vlc"));
        assert_eq!(players[index.unwrap()].suffix(), "vlc");
        assert_eq!(reason, ChoiceReason::Pinned);

        // Pinned to a player that has left: the rule takes over rather than going blank.
        let (index, reason) = choose(&players, Some("org.mpris.MediaPlayer2.gone"));
        assert_eq!(players[index.unwrap()].suffix(), "mpd");
        assert_eq!(reason, ChoiceReason::Playing);
    }

    #[test]
    fn a_browser_bus_is_shadowed_only_while_plasma_integration_is_present() {
        let alone = names(&["chromium.instance_2_51"]);
        assert_eq!(shadow_of(&alone[0], &alone), None);

        let both = names(&["chromium.instance_2_51", "plasma-browser-integration"]);
        assert_eq!(shadow_of(&both[0], &both), Some(Shadowed::PlasmaIntegration));
        assert_eq!(shadow_of(&both[1], &both), None);

        let firefox = names(&["firefox.instance_1", "plasma-browser-integration"]);
        assert_eq!(shadow_of(&firefox[0], &firefox), Some(Shadowed::PlasmaIntegration));
    }

    #[test]
    fn playerctld_and_per_instance_mpd_buses_are_shadows_of_whoever_they_copy() {
        let all = names(&["playerctld", "mpd", "beets.mpd"]);
        assert_eq!(shadow_of(&all[0], &all), Some(Shadowed::Playerctld));
        assert_eq!(shadow_of(&all[1], &all), None);
        assert_eq!(shadow_of(&all[2], &all), Some(Shadowed::MpdInstance));

        assert_eq!(shadow_of("org.kde.StatusNotifierWatcher", &all), None);
    }

    #[test]
    fn a_shadow_is_still_chosen_when_it_is_all_there_is() {
        let all = names(&["playerctld"]);
        let players = vec![player(
            "playerctld",
            PlaybackStatus::Playing,
            Duration::from_secs(1),
            &all,
        )];

        let (index, reason) = choose(&players, None);
        assert_eq!(players[index.unwrap()].suffix(), "playerctld");
        assert_eq!(reason, ChoiceReason::Only);
    }

    #[test]
    fn an_empty_bus_chooses_nothing_and_says_so() {
        assert_eq!(choose(&[], None), (None, ChoiceReason::Nothing));
    }
}
