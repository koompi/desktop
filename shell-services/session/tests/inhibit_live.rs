//! D16's proof, against the real logind on this seat: the lock is the fd.
//!
//! `Idle.qml:53-58` holds a lock by keeping `systemd-inhibit ... sleep infinity`
//! alive and releases it with `pkill -f`. This takes the same kind of lock with no
//! subprocess and releases it by dropping a value.
//!
//! Ignored by default because it needs the system bus and a logind session. It takes
//! only `idle`, never `sleep` or `shutdown`, and the fd closes when this process exits
//! whatever happens, so an orphaned lock is not reachable from here.
//!
//! ```text
//! cargo test -p koompi-session --test inhibit_live -- --ignored --nocapture
//! ```

use std::process::Command;

use koompi_session::{Mode, SessionConfig, SessionService, What};

fn systemd_inhibit_list() -> String {
    let output = Command::new("systemd-inhibit")
        .arg("--list")
        .output()
        .expect("systemd-inhibit");
    String::from_utf8_lossy(&output.stdout).into_owned()
}

#[tokio::test]
#[ignore = "takes a real inhibitor on this seat: run with --ignored"]
async fn a_block_inhibitor_appears_in_systemd_inhibit_list_and_leaves_when_dropped() {
    let config = SessionConfig {
        who: "koompi-session-j09".to_owned(),
        ..SessionConfig::default()
    };
    let service = SessionService::connect(config).await.unwrap();

    let before = systemd_inhibit_list();
    assert!(
        !before.contains("koompi-session-j09"),
        "a lock from an earlier run is still held:\n{before}"
    );

    let inhibitor = service
        .inhibit(What::IDLE, "J09 acceptance item 3", Mode::Block)
        .await
        .unwrap();

    let held = systemd_inhibit_list();
    println!("--- systemd-inhibit --list while held ---\n{held}");
    assert!(
        held.contains("koompi-session-j09"),
        "the lock never appeared"
    );
    assert!(held.contains("J09 acceptance item 3"));

    let listed = service.list_inhibitors().await.unwrap();
    let ours = listed
        .iter()
        .find(|row| row.who == "koompi-session-j09")
        .expect("the crate cannot see its own lock");
    assert_eq!(ours.what, What::IDLE);
    assert_eq!(ours.mode, Some(Mode::Block));
    assert_eq!(ours.pid, std::process::id());
    assert_eq!(ours.uid, nix_uid());

    // The whole delta: no `pkill -f`, no pattern, no subprocess. Closing the fd is it.
    inhibitor.release();

    let after = systemd_inhibit_list();
    println!("--- systemd-inhibit --list after release ---\n{after}");
    assert!(
        !after.contains("koompi-session-j09"),
        "the lock outlived the value that held it:\n{after}"
    );
    assert!(!service
        .list_inhibitors()
        .await
        .unwrap()
        .iter()
        .any(|row| row.who == "koompi-session-j09"));

    // The shell's own lock, which this job must not disturb, is still there.
    assert!(
        after.contains("quickshell"),
        "Idle.qml's keep-awake lock went missing:\n{after}"
    );
}

/// A `delay` lock on `sleep` is the one a lock screen needs, so it is worth proving it
/// can be taken. Nothing suspends: the lock is released without a sleep ever starting.
#[tokio::test]
#[ignore = "takes a real inhibitor on this seat: run with --ignored"]
async fn a_delay_inhibitor_on_sleep_is_taken_and_released_without_anything_sleeping() {
    let config = SessionConfig {
        who: "koompi-session-j09-delay".to_owned(),
        ..SessionConfig::default()
    };
    let service = SessionService::connect(config).await.unwrap();

    let inhibitor = service
        .inhibit(What::SLEEP, "lock the screen before sleeping", Mode::Delay)
        .await
        .unwrap();
    assert_eq!(inhibitor.mode(), Mode::Delay);

    let held = systemd_inhibit_list();
    println!("--- delay lock held ---\n{held}");
    assert!(held.contains("koompi-session-j09-delay"));

    drop(inhibitor);
    assert!(!systemd_inhibit_list().contains("koompi-session-j09-delay"));
}

#[tokio::test]
#[ignore = "needs the system bus: run with --ignored"]
async fn an_inhibitor_that_blocks_nothing_is_refused_before_it_reaches_the_bus() {
    let service = SessionService::connect(SessionConfig::default())
        .await
        .unwrap();
    assert!(service
        .inhibit(What::NONE, "nothing", Mode::Block)
        .await
        .is_err());
}

fn nix_uid() -> u32 {
    std::fs::read_to_string("/proc/self/status")
        .unwrap()
        .lines()
        .find_map(|line| line.strip_prefix("Uid:"))
        .and_then(|line| line.split_whitespace().next().map(str::to_owned))
        .unwrap()
        .parse()
        .unwrap()
}
