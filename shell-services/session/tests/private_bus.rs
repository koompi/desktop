//! The signal half, against a logind that is not this machine's.
//!
//! `Lock`, `Unlock` and `PrepareForSleep` are the events a shell has to get right, and
//! two of the three cannot be provoked on a seat someone is logged into: locking the
//! session puts a lock screen over the user's work, and `PrepareForSleep` only arrives
//! because the machine is going down. So a fake `org.freedesktop.login1` serves them
//! on a private bus and the real service subscribes to it.
//!
//! Ignored by default because it needs a bus of its own:
//!
//! ```text
//! dbus-run-session -- cargo test -p koompi-session --test private_bus -- --ignored
//! ```

use std::os::fd::OwnedFd;
use std::time::Duration;

use koompi_service::Service;
use koompi_session::{Mode, SessionConfig, SessionEvent, SessionService, What};
use zbus::object_server::SignalEmitter;
use zbus::Connection;
use zvariant::{ObjectPath, OwnedObjectPath};

const MANAGER_PATH: &str = "/org/freedesktop/login1";
const SESSION_PATH: &str = "/org/freedesktop/login1/session/_32";
const SEAT_PATH: &str = "/org/freedesktop/login1/seat/seat0";

struct Manager;

#[zbus::interface(name = "org.freedesktop.login1.Manager")]
impl Manager {
    async fn get_session(&self, _id: &str) -> zbus::fdo::Result<OwnedObjectPath> {
        Ok(ObjectPath::try_from(SESSION_PATH).unwrap().into())
    }

    #[zbus(name = "GetSessionByPID")]
    async fn get_session_by_pid(&self, _pid: u32) -> zbus::fdo::Result<OwnedObjectPath> {
        Ok(ObjectPath::try_from(SESSION_PATH).unwrap().into())
    }

    async fn can_power_off(&self) -> String {
        "yes".to_owned()
    }

    async fn can_reboot(&self) -> String {
        "challenge".to_owned()
    }

    /// The reply this seat really gives, and the one the QML grep reads as "no".
    async fn can_suspend(&self) -> String {
        "inhibited".to_owned()
    }

    async fn can_hibernate(&self) -> String {
        "na".to_owned()
    }

    async fn can_hybrid_sleep(&self) -> String {
        "inhibitor-blocked".to_owned()
    }

    async fn can_suspend_then_hibernate(&self) -> String {
        "challenge-inhibitor-blocked".to_owned()
    }

    async fn inhibit(
        &self,
        _what: &str,
        _who: &str,
        _why: &str,
        _mode: &str,
    ) -> zbus::fdo::Result<zvariant::OwnedFd> {
        let (held, _peer) = std::os::unix::net::UnixStream::pair()
            .map_err(|error| zbus::fdo::Error::Failed(error.to_string()))?;
        Ok(OwnedFd::from(held).into())
    }

    async fn list_inhibitors(&self) -> Vec<(String, String, String, String, u32, u32)> {
        vec![(
            "sleep:idle:handle-lid-switch".to_owned(),
            "quickshell".to_owned(),
            "Keep system awake".to_owned(),
            "block".to_owned(),
            1000,
            418610,
        )]
    }

    #[zbus(property)]
    async fn preparing_for_sleep(&self) -> bool {
        false
    }

    #[zbus(property)]
    async fn preparing_for_shutdown(&self) -> bool {
        false
    }

    #[zbus(property)]
    async fn block_inhibited(&self) -> String {
        "sleep:idle:handle-lid-switch".to_owned()
    }

    #[zbus(property)]
    async fn delay_inhibited(&self) -> String {
        "sleep".to_owned()
    }

    #[zbus(signal)]
    async fn prepare_for_sleep(emitter: &SignalEmitter<'_>, start: bool) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn prepare_for_shutdown(emitter: &SignalEmitter<'_>, start: bool) -> zbus::Result<()>;
}

struct Session;

#[zbus::interface(name = "org.freedesktop.login1.Session")]
impl Session {
    #[zbus(property)]
    async fn id(&self) -> String {
        "2".to_owned()
    }

    #[zbus(property)]
    async fn name(&self) -> String {
        "userx".to_owned()
    }

    #[zbus(property)]
    async fn user(&self) -> (u32, OwnedObjectPath) {
        (
            1000,
            ObjectPath::try_from("/org/freedesktop/login1/user/_1000")
                .unwrap()
                .into(),
        )
    }

    #[zbus(property)]
    async fn class(&self) -> String {
        "user".to_owned()
    }

    #[zbus(property, name = "Type")]
    async fn kind(&self) -> String {
        "wayland".to_owned()
    }

    #[zbus(property)]
    async fn state(&self) -> String {
        "active".to_owned()
    }

    #[zbus(property)]
    async fn active(&self) -> bool {
        true
    }

    #[zbus(property)]
    async fn locked_hint(&self) -> bool {
        false
    }

    #[zbus(property)]
    async fn idle_hint(&self) -> bool {
        false
    }

    #[zbus(property)]
    async fn can_lock(&self) -> bool {
        true
    }

    #[zbus(property)]
    async fn can_idle(&self) -> bool {
        true
    }

    #[zbus(property)]
    async fn desktop(&self) -> String {
        "KOOMPI:Hyprland".to_owned()
    }

    #[zbus(property, name = "TTY")]
    async fn tty(&self) -> String {
        "tty1".to_owned()
    }

    #[zbus(property, name = "VTNr")]
    async fn vt_nr(&self) -> u32 {
        1
    }

    #[zbus(property)]
    async fn remote(&self) -> bool {
        false
    }

    #[zbus(property)]
    async fn service(&self) -> String {
        "sddm".to_owned()
    }

    #[zbus(property)]
    async fn scope(&self) -> String {
        "session-2.scope".to_owned()
    }

    #[zbus(property)]
    async fn leader(&self) -> u32 {
        989
    }

    #[zbus(property)]
    async fn seat(&self) -> (String, OwnedObjectPath) {
        (
            "seat0".to_owned(),
            ObjectPath::try_from(SEAT_PATH).unwrap().into(),
        )
    }

    #[zbus(signal)]
    async fn lock(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn unlock(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

struct Seat;

#[zbus::interface(name = "org.freedesktop.login1.Seat")]
impl Seat {
    #[zbus(property)]
    async fn id(&self) -> String {
        "seat0".to_owned()
    }

    #[zbus(property)]
    async fn can_graphical(&self) -> bool {
        true
    }

    #[zbus(property, name = "CanTTY")]
    async fn can_tty(&self) -> bool {
        true
    }

    #[zbus(property)]
    async fn idle_hint(&self) -> bool {
        false
    }

    #[zbus(property)]
    async fn active_session(&self) -> (String, OwnedObjectPath) {
        (
            "2".to_owned(),
            ObjectPath::try_from(SESSION_PATH).unwrap().into(),
        )
    }

    #[zbus(property)]
    async fn sessions(&self) -> Vec<(String, OwnedObjectPath)> {
        vec![(
            "2".to_owned(),
            ObjectPath::try_from(SESSION_PATH).unwrap().into(),
        )]
    }
}

async fn fake_logind() -> Connection {
    zbus::connection::Builder::session()
        .unwrap()
        .name("org.freedesktop.login1")
        .unwrap()
        .serve_at(MANAGER_PATH, Manager)
        .unwrap()
        .serve_at(SESSION_PATH, Session)
        .unwrap()
        .serve_at(SEAT_PATH, Seat)
        .unwrap()
        .build()
        .await
        .unwrap()
}

async fn client() -> SessionService {
    let conn = Connection::session().await.unwrap();
    SessionService::with_connection(
        conn,
        SessionConfig {
            session_id: Some("2".to_owned()),
            ..SessionConfig::default()
        },
    )
    .await
    .unwrap()
}

async fn emitter(conn: &Connection, path: &'static str) -> SignalEmitter<'static> {
    SignalEmitter::new(conn, path).unwrap()
}

async fn next_event(events: &mut tokio::sync::broadcast::Receiver<SessionEvent>) -> SessionEvent {
    tokio::time::timeout(Duration::from_secs(5), events.recv())
        .await
        .expect("no event within five seconds")
        .expect("the event channel closed")
}

#[tokio::test]
#[ignore = "needs a private bus: dbus-run-session -- cargo test --test private_bus -- --ignored"]
async fn the_seat_reads_back_the_way_loginctl_prints_it() {
    let _logind = fake_logind().await;
    let service = client().await;
    let state = service.state();

    assert_eq!(state.session.id, "2");
    assert_eq!(state.session.kind, "wayland");
    assert_eq!(state.session.class, "user");
    assert_eq!(state.session.state, "active");
    assert!(state.session.active);
    assert!(!state.session.locked_hint);
    assert_eq!(state.session.leader, 989);
    assert_eq!(state.session.service, "sddm");
    assert!(state.session.leader_is_display_manager_helper());
    assert_eq!(state.seat.as_ref().unwrap().id, "seat0");
    assert!(state.seat.as_ref().unwrap().can_graphical);
    assert_eq!(
        state.block_inhibited,
        What::parse("idle:sleep:handle-lid-switch")
    );
    assert_eq!(state.delay_inhibited, What::SLEEP);
}

/// All six `Can*` methods over the bus, with a different reply form on each, so the
/// decode is exercised end to end rather than only in the parser's own test.
#[tokio::test]
#[ignore = "needs a private bus: dbus-run-session -- cargo test --test private_bus -- --ignored"]
async fn six_capability_replies_survive_the_round_trip_intact() {
    let _logind = fake_logind().await;
    let capabilities = client().await.capabilities();

    assert_eq!(capabilities.power_off.as_str(), "yes");
    assert_eq!(capabilities.reboot.as_str(), "challenge");
    assert_eq!(capabilities.suspend.as_str(), "inhibited");
    assert_eq!(capabilities.hibernate.as_str(), "na");
    assert_eq!(capabilities.hybrid_sleep.as_str(), "inhibitor-blocked");
    assert_eq!(
        capabilities.suspend_then_hibernate.as_str(),
        "challenge-inhibitor-blocked"
    );

    assert!(capabilities.power_off.offered());
    assert!(capabilities.reboot.offered());
    assert!(!capabilities.suspend.offered());
    assert!(capabilities.suspend.permitted());
    assert!(!capabilities.hybrid_sleep.permitted());
}

/// Acceptance item 5, done here rather than by running `loginctl lock-session` against
/// a seat with the user's work on it.
#[tokio::test]
#[ignore = "needs a private bus: dbus-run-session -- cargo test --test private_bus -- --ignored"]
async fn the_lock_and_unlock_signals_reach_a_subscriber() {
    let logind = fake_logind().await;
    let service = client().await;
    let mut events = service.events();
    let emitter = emitter(&logind, SESSION_PATH).await;

    Session::lock(&emitter).await.unwrap();
    assert!(matches!(next_event(&mut events).await, SessionEvent::Lock));

    Session::unlock(&emitter).await.unwrap();
    assert!(matches!(
        next_event(&mut events).await,
        SessionEvent::Unlock
    ));
}

/// The one event where the ordering is visible to the user. Nothing sleeps: the fake
/// emits the signal and the machine never hears about it.
#[tokio::test]
#[ignore = "needs a private bus: dbus-run-session -- cargo test --test private_bus -- --ignored"]
async fn prepare_for_sleep_arrives_in_both_directions_and_carries_the_delay_hold() {
    let logind = fake_logind().await;
    let conn = Connection::session().await.unwrap();
    let service = SessionService::with_connection(
        conn,
        SessionConfig {
            session_id: Some("2".to_owned()),
            delay_sleep: Some("lock the screen before sleeping".to_owned()),
            ..SessionConfig::default()
        },
    )
    .await
    .unwrap();
    let mut events = service.events();
    let emitter = emitter(&logind, MANAGER_PATH).await;

    Manager::prepare_for_sleep(&emitter, true).await.unwrap();
    match next_event(&mut events).await {
        SessionEvent::PrepareForSleep {
            going_to_sleep,
            hold,
        } => {
            assert!(going_to_sleep);
            assert!(
                hold.is_some(),
                "the delay inhibitor was configured but never handed over, so logind \
                 would sleep before anything could lock"
            );
        }
        other => panic!("{other:?}"),
    }

    Manager::prepare_for_sleep(&emitter, false).await.unwrap();
    match next_event(&mut events).await {
        SessionEvent::PrepareForSleep {
            going_to_sleep,
            hold,
        } => {
            assert!(!going_to_sleep);
            assert!(hold.is_none(), "waking up is not something to delay");
        }
        other => panic!("{other:?}"),
    }
}

#[tokio::test]
#[ignore = "needs a private bus: dbus-run-session -- cargo test --test private_bus -- --ignored"]
async fn prepare_for_shutdown_reaches_a_subscriber() {
    let logind = fake_logind().await;
    let service = client().await;
    let mut events = service.events();
    let emitter = emitter(&logind, MANAGER_PATH).await;

    Manager::prepare_for_shutdown(&emitter, true).await.unwrap();
    assert!(matches!(
        next_event(&mut events).await,
        SessionEvent::PrepareForShutdown {
            shutting_down: true
        }
    ));
}

/// The lock is the fd all the way through: taken over the bus, held by a value, gone
/// when the value goes.
#[tokio::test]
#[ignore = "needs a private bus: dbus-run-session -- cargo test --test private_bus -- --ignored"]
async fn an_inhibitor_taken_over_the_bus_is_an_open_descriptor() {
    use std::os::fd::AsFd;

    let _logind = fake_logind().await;
    let service = client().await;

    let inhibitor = service
        .inhibit(What::IDLE | What::SLEEP, "held", Mode::Block)
        .await
        .unwrap();
    assert_eq!(inhibitor.what().as_wire(), "sleep:idle");
    assert_eq!(inhibitor.who(), "koompi-shell");
    assert_eq!(inhibitor.mode(), Mode::Block);
    // An fd that is not open cannot be duplicated.
    inhibitor.as_fd().try_clone_to_owned().unwrap();

    let listed = service.list_inhibitors().await.unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].who, "quickshell");
    assert_eq!(listed[0].what.as_wire(), "sleep:idle:handle-lid-switch");
    assert_eq!(listed[0].mode, Some(Mode::Block));
}
