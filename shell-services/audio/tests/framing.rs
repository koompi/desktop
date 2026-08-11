//! NDJSON framing against a session captured from the real daemon, plus the two lines a
//! reader has to survive: one cut in half, and one that was never JSON.
//!
//! `tests/fixtures/session.ndjson` is `audiod` stdout recorded while `pw-play` played four
//! seconds of silence, then `ping`, an unknown command and `quit`.

use koompi_audio::{AudioState, Message};

const SESSION: &str = include_str!("fixtures/session.ndjson");

fn lines() -> Vec<&'static str> {
    SESSION.lines().filter(|line| !line.is_empty()).collect()
}

fn replay(upto: usize) -> AudioState {
    let mut state = AudioState::default();
    for line in lines().iter().take(upto) {
        state.apply(&Message::parse(line).expect(line));
    }
    state
}

#[test]
fn the_captured_session_replays_into_the_state_the_daemon_described() {
    let state = replay(2);

    assert!(state.ready);
    assert_eq!(state.serial, 1);
    assert_eq!(
        state.default_sink.as_deref(),
        Some("alsa_output.pci-0000_00_1f.3-platform-sof_sdw.HiFi__Speaker__sink")
    );
    assert_eq!(
        state.output_devices.iter().map(|n| n.id).collect::<Vec<_>>(),
        [34, 85, 86, 87, 88, 89]
    );
    assert_eq!(
        state.input_devices.iter().map(|n| n.id).collect::<Vec<_>>(),
        [35, 90, 91]
    );

    let sink = state.sink().expect("a default sink");
    assert_eq!(sink.id, 85);
    assert_eq!(sink.friendly_name(), "Speaker");
    assert_eq!(sink.volume, Some(0.681671142578125));
    assert_eq!(sink.channel_volumes.len(), 2);
    assert_eq!(sink.mute, Some(false));
    assert_eq!(state.source().map(|node| node.id), Some(90));
}

#[test]
fn a_stream_appears_becomes_ready_and_goes_away() {
    let added = replay(3);
    let stream = added.node(115).expect("the pw-play stream");
    assert!(stream.is_stream && stream.is_sink);
    assert_eq!(added.output_streams.len(), 1);
    assert_eq!(stream.display_name(), "pw-play");
    assert!(!stream.ready);
    assert_eq!(stream.volume, None);

    let ready = replay(4);
    let stream = ready.node(115).expect("the pw-play stream");
    assert!(stream.ready);
    assert_eq!(stream.volume, Some(1.5));
    assert_eq!(ready.output_streams.len(), 1);

    let removed = replay(5);
    assert!(removed.node(115).is_none());
    assert!(removed.output_streams.is_empty());
    assert_eq!(removed.output_devices.len(), 6);
}

#[test]
fn replies_carry_the_daemon_verdict_and_move_no_state() {
    let before = replay(5);
    let after = replay(lines().len());
    assert_eq!(before, after);

    let Message::Reply(ok) = Message::parse(lines()[5]).unwrap() else {
        panic!("line 6 is a reply");
    };
    assert_eq!(ok.id, Some(1));
    assert!(ok.outcome().is_ok());

    let Message::Reply(failed) = Message::parse(lines()[6]).unwrap() else {
        panic!("line 7 is a reply");
    };
    let error = failed.outcome().unwrap_err().to_string();
    assert!(error.contains("unknown_command"), "{error}");
}

#[test]
fn a_line_cut_in_half_is_rejected_and_does_not_poison_the_state() {
    let full = lines()[1];
    let truncated = &full[..full.len() / 2];

    assert!(Message::parse(truncated).is_err());

    let mut state = AudioState::default();
    for line in [truncated, full] {
        if let Ok(message) = Message::parse(line) {
            state.apply(&message);
        }
    }
    assert!(state.ready);
    assert_eq!(state.output_devices.len(), 6);
}

#[test]
fn a_line_that_is_not_json_is_skipped_and_the_next_one_still_lands() {
    let mut state = AudioState::default();
    let mut applied = 0;

    for line in ["", "this is not json", "[1,2,3]", lines()[1], "\0garbage"] {
        if let Ok(message) = Message::parse(line) {
            state.apply(&message);
            applied += 1;
        }
    }

    assert_eq!(applied, 1);
    assert!(state.ready);
    assert_eq!(state.sink().map(|node| node.id), Some(85));
}

/// The protocol says a reader ignores what it does not know, so the daemon can grow a
/// message type without a version bump.
#[test]
fn an_unknown_message_type_leaves_the_state_alone() {
    let mut state = replay(2);
    let before = state.clone();

    let unknown = Message::parse(r#"{"type":"latency_changed","node":85,"quantum":1024}"#).unwrap();
    assert_eq!(unknown, Message::Unknown);
    assert!(!state.apply(&unknown));
    assert_eq!(state, before);
}
