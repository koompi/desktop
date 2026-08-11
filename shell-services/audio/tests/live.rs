//! The command path against the daemon that is actually running, since a reply built by a
//! fake proves nothing about the seam.
//!
//!     cargo test -p koompi-audio -- --ignored
//!
//! Read-only against the seat by construction: the only volume and mute it writes are the
//! ones the daemon reported a moment earlier, which the protocol says produces no change
//! and therefore no event.

use koompi_audio::AudioService;
use koompi_service::{PollRate, Service};

#[tokio::test]
#[ignore = "drives the real audiod against the live pipewire session"]
async fn the_daemon_answers_every_command_this_crate_builds() {
    let service = AudioService::start(PollRate::NORMAL).expect("an audiod binary");
    let state = service.ready().await.expect("a pipewire session");

    let hello = service.status().hello.expect("hello");
    assert_eq!(hello.protocol, koompi_audio::PROTOCOL_VERSION);
    assert_eq!(hello.daemon, "audiod");

    service.ping().await.expect("ping");

    let serial = state.serial;
    service.refresh().await.expect("get_state");
    assert!(
        service.state().serial > serial,
        "get_state did not advance the snapshot serial"
    );

    let sink = state.sink().expect("a default sink").clone();
    let volume = sink.volume.expect("a ready sink has a volume");
    let mute = sink.mute.expect("a ready sink has a mute");

    service.set_volume(sink.id, volume).await.expect("set_volume");
    service.set_mute(sink.id, mute).await.expect("set_mute");

    let error = service
        .set_volume(999_999, volume)
        .await
        .expect_err("a node that does not exist");
    assert!(error.to_string().contains("unknown_node"), "{error}");

    let after = service.state().sink().cloned().expect("the sink is still there");
    assert_eq!(after.id, sink.id);
    assert_eq!(after.volume, Some(volume));
    assert_eq!(after.mute, Some(mute));
    assert_eq!(service.state().default_sink, state.default_sink);
}
