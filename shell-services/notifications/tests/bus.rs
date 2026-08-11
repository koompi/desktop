//! Everything here claims `org.freedesktop.Notifications`, so everything here needs a bus of
//! its own and refuses to run on one that is not.
//!
//! `dbus-run-session -- cargo test -p koompi-notifications --test bus -- --ignored --test-threads=1`
//!
//! On this seat Quickshell owns that name. A second owner on the session bus takes every
//! notification away from the desktop, which is why [`private_bus`] asserts the bus is empty
//! before any of these run, and why they are `#[ignore]`d rather than left to a bare
//! `cargo test`.

use std::collections::HashMap;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use futures_util::StreamExt;
use koompi_notifications::{
    CloseReason, NotificationEvent, NotificationService, NotificationsConfig, BUS_NAME,
};
use koompi_service::Service;
use tokio::sync::Mutex;
use zbus::{Connection, Result as BusResult};
use zvariant::{Structure, Value};

/// One bus, one notification daemon name. The tests take it in turn.
static NAME: Mutex<()> = Mutex::const_new(());

#[zbus::proxy(
    interface = "org.freedesktop.Notifications",
    default_service = "org.freedesktop.Notifications",
    default_path = "/org/freedesktop/Notifications"
)]
trait Notifications {
    #[allow(clippy::too_many_arguments)]
    fn notify(
        &self,
        app_name: &str,
        replaces_id: u32,
        app_icon: &str,
        summary: &str,
        body: &str,
        actions: &[&str],
        hints: HashMap<&str, Value<'_>>,
        expire_timeout: i32,
    ) -> BusResult<u32>;

    fn close_notification(&self, id: u32) -> BusResult<()>;

    fn get_capabilities(&self) -> BusResult<Vec<String>>;

    fn get_server_information(&self) -> BusResult<(String, String, String, String)>;

    #[zbus(signal)]
    fn notification_closed(&self, id: u32, reason: u32) -> BusResult<()>;

    #[zbus(signal)]
    fn action_invoked(&self, id: u32, action_key: String) -> BusResult<()>;
}

/// The guard on this job's first stop condition. A bus from `dbus-run-session` has exactly
/// one well-known name; a session bus with a desktop on it has dozens.
///
/// The wait is for the previous test's connection, which the bus tears down a moment after
/// the test that owned it ended. A shared bus never converges on this, so waiting costs the
/// guard nothing and stops one failure from being reported as three.
async fn private_bus() -> Connection {
    let conn = Connection::session()
        .await
        .expect("no session bus; run under dbus-run-session");
    let dbus = zbus::fdo::DBusProxy::new(&conn).await.unwrap();

    let deadline = Instant::now() + Duration::from_secs(2);
    let mut well_known = Vec::new();
    while Instant::now() < deadline {
        well_known = dbus
            .list_names()
            .await
            .unwrap()
            .iter()
            .map(|name| name.to_string())
            .filter(|name| !name.starts_with(':'))
            .collect();
        if well_known == ["org.freedesktop.DBus"] {
            return conn;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }

    panic!("refusing to touch a bus that is not private, it holds {well_known:?}: run under dbus-run-session");
}

fn scratch(name: &str) -> PathBuf {
    let directory = PathBuf::from("/tmp/j07-notifications").join(format!("bus-{name}"));
    let _ = std::fs::remove_dir_all(&directory);
    std::fs::create_dir_all(&directory).unwrap();
    directory.join("notifications.json")
}

fn config(name: &str, default_timeout: Duration) -> NotificationsConfig {
    NotificationsConfig {
        history_path: scratch(name),
        default_timeout,
        ..NotificationsConfig::default()
    }
}

async fn started(name: &str, default_timeout: Duration) -> (Connection, NotificationService) {
    let conn = private_bus().await;
    let service = NotificationService::serve_on(conn.clone(), config(name, default_timeout))
        .await
        .unwrap();
    service
        .own_name()
        .await
        .expect("empty bus refused the name");
    (conn, service)
}

async fn client() -> NotificationsProxy<'static> {
    NotificationsProxy::new(&Connection::session().await.unwrap())
        .await
        .unwrap()
}

async fn settle() {
    tokio::time::sleep(Duration::from_millis(120)).await;
}

/// 2x2 RGBA with the padded stride a real GdkPixbuf hands over.
fn image_hint() -> Value<'static> {
    let pixels: Vec<u8> = vec![
        0xff, 0x00, 0x00, 0xff, 0x00, 0xff, 0x00, 0xff, 0xde, 0xad, 0x00, 0x00, 0xff, 0xff, 0xff,
        0xff, 0x00, 0x80,
    ];
    Value::from(Structure::from((
        2i32, 2i32, 10i32, true, 8i32, 4i32, pixels,
    )))
}

#[tokio::test]
#[ignore = "claims org.freedesktop.Notifications; private bus only"]
async fn a_notification_arrives_decoded_and_lands_in_the_history() {
    let _held = NAME.lock().await;
    let (conn, service) = started("arrives", Duration::from_millis(7000)).await;
    let mut events = service.events();

    let hints = HashMap::from([
        ("urgency", Value::U8(2)),
        ("image-data", image_hint()),
        ("desktop-entry", Value::from("org.telegram.desktop")),
        ("transient", Value::Bool(true)),
        ("x-kde-reply-placeholder-text", Value::from("Reply")),
    ]);
    let id = client()
        .await
        .notify(
            "Telegram",
            0,
            "file:///usr/share/icons/hicolor/48x48/apps/telegram.png",
            "Ada",
            "are you there",
            &["reply", "Reply", "mute", "Mute"],
            hints,
            -1,
        )
        .await
        .unwrap();
    assert_ne!(id, 0, "0 is the spec's 'no id'");

    let NotificationEvent::Posted(posted) = events.recv().await.unwrap() else {
        panic!("the first event was not the arrival");
    };
    assert_eq!(posted.id, id);
    assert_eq!(posted.app_name, "Telegram");
    assert_eq!(
        posted.app_icon,
        koompi_notifications::Icon::Path("/usr/share/icons/hicolor/48x48/apps/telegram.png".into()),
        "the file:// URI was not resolved to a path"
    );
    assert_eq!(posted.summary, "Ada");
    assert_eq!(posted.body, "are you there");
    assert_eq!(posted.actions.len(), 2);
    assert_eq!(posted.actions[0].identifier, "reply");
    assert_eq!(posted.actions[0].text, "Reply");
    assert_eq!(
        posted.hints.urgency,
        koompi_notifications::Urgency::Critical
    );
    assert_eq!(
        posted.hints.desktop_entry.as_deref(),
        Some("org.telegram.desktop")
    );
    assert!(posted.hints.transient);
    assert!(posted
        .hints
        .other
        .contains_key("x-kde-reply-placeholder-text"));

    let image = posted.hints.image.expect("image-data did not survive");
    assert_eq!((image.width, image.height, image.rowstride), (2, 2, 10));
    assert_eq!(image.bytes.len(), 18, "the bytes were rescaled");

    assert_eq!(service.state().list.len(), 1);
    assert!(service.state().popups().count() == 1);

    settle().await;
    let written = std::fs::read_to_string(service.history_path()).unwrap();
    let history: serde_json::Value = serde_json::from_str(&written).unwrap();
    assert_eq!(history[0]["notificationId"], id);
    assert_eq!(history[0]["appName"], "Telegram");
    assert_eq!(history[0]["urgency"], "2");

    conn.release_name(BUS_NAME).await.unwrap();
}

#[tokio::test]
#[ignore = "claims org.freedesktop.Notifications; private bus only"]
async fn replaces_id_edits_the_entry_instead_of_adding_one() {
    let _held = NAME.lock().await;
    let (conn, service) = started("replaces", Duration::from_millis(7000)).await;
    let client = client().await;

    let first = client
        .notify("app", 0, "", "downloading", "0%", &[], HashMap::new(), 0)
        .await
        .unwrap();
    settle().await;
    assert_eq!(service.state().list.len(), 1);
    assert_eq!(service.state().get(first).unwrap().body, "0%");

    let second = client
        .notify(
            "app",
            first,
            "",
            "downloading",
            "100%",
            &[],
            HashMap::new(),
            0,
        )
        .await
        .unwrap();

    assert_eq!(second, first, "the spec says the reply is replaces_id");
    settle().await;
    let state = service.state();
    assert_eq!(state.list.len(), 1, "a replacement was appended");
    assert_eq!(state.get(first).unwrap().body, "100%");

    // And a fresh notification afterwards does not collide with the id it was given.
    let third = client
        .notify("app", 0, "", "done", "", &[], HashMap::new(), 0)
        .await
        .unwrap();
    assert_ne!(third, first);
    settle().await;
    assert_eq!(service.state().list.len(), 2);

    conn.release_name(BUS_NAME).await.unwrap();
}

#[tokio::test]
#[ignore = "claims org.freedesktop.Notifications; private bus only"]
async fn zero_never_expires_and_minus_one_expires_at_the_server_default() {
    let _held = NAME.lock().await;
    let default = Duration::from_millis(600);
    let (conn, service) = started("expiry", default).await;
    let client = client().await;

    let forever = client
        .notify("app", 0, "", "pinned", "", &[], HashMap::new(), 0)
        .await
        .unwrap();
    let started_at = Instant::now();
    let expiring = client
        .notify("app", 0, "", "fleeting", "", &[], HashMap::new(), -1)
        .await
        .unwrap();

    let mut closed = client.receive_notification_closed().await.unwrap();
    let signal = tokio::time::timeout(default * 4, closed.next())
        .await
        .expect("nothing expired at the server default")
        .unwrap();
    let elapsed = started_at.elapsed();
    let (id, reason) = signal
        .args()
        .map(|args| (*args.id(), *args.reason()))
        .unwrap();

    assert_eq!(id, expiring);
    assert_eq!(reason, CloseReason::Expired.as_u32());
    assert!(
        elapsed >= default && elapsed < default * 3,
        "expired after {elapsed:?}, not around the {default:?} default"
    );

    let state = service.state();
    assert!(
        state.get(forever).unwrap().popup,
        "expire_timeout 0 expired"
    );
    assert!(
        !state.get(expiring).unwrap().popup,
        "the expired popup is still up"
    );
    assert_eq!(
        state.list.len(),
        2,
        "expiry deleted a history entry that was not transient"
    );

    conn.release_name(BUS_NAME).await.unwrap();
}

#[tokio::test]
#[ignore = "claims org.freedesktop.Notifications; private bus only"]
async fn an_invoked_action_reaches_the_sender_and_then_closes_the_notification() {
    let _held = NAME.lock().await;
    let (conn, service) = started("actions", Duration::from_millis(7000)).await;
    let client = client().await;
    let mut invoked = client.receive_action_invoked().await.unwrap();
    let mut closed = client.receive_notification_closed().await.unwrap();

    let id = client
        .notify(
            "app",
            0,
            "",
            "question",
            "pick one",
            &["yes", "Yes", "no", "No"],
            HashMap::new(),
            0,
        )
        .await
        .unwrap();
    settle().await;

    service.invoke_action(id, "yes").await.unwrap();

    let signal = tokio::time::timeout(Duration::from_secs(5), invoked.next())
        .await
        .expect("no ActionInvoked reached the sender")
        .unwrap();
    let args = signal.args().unwrap();
    assert_eq!(*args.id(), id);
    assert_eq!(args.action_key(), &"yes");

    let signal = tokio::time::timeout(Duration::from_secs(5), closed.next())
        .await
        .expect("the notification was not closed after its action ran")
        .unwrap();
    assert_eq!(
        *signal.args().unwrap().reason(),
        CloseReason::Dismissed.as_u32()
    );
    assert!(service.state().list.is_empty());

    assert!(
        service.invoke_action(id, "yes").await.is_err(),
        "an action on a notification that is gone reported success"
    );

    conn.release_name(BUS_NAME).await.unwrap();
}

#[tokio::test]
#[ignore = "claims org.freedesktop.Notifications; private bus only"]
async fn close_notification_says_which_reason_it_was_and_a_stale_id_is_not_an_error() {
    let _held = NAME.lock().await;
    let (conn, service) = started("close", Duration::from_millis(7000)).await;
    let client = client().await;
    let mut closed = client.receive_notification_closed().await.unwrap();

    let id = client
        .notify("app", 0, "", "transfer", "", &[], HashMap::new(), 0)
        .await
        .unwrap();
    settle().await;
    client.close_notification(id).await.unwrap();

    let signal = tokio::time::timeout(Duration::from_secs(5), closed.next())
        .await
        .expect("CloseNotification emitted nothing")
        .unwrap();
    let args = signal.args().unwrap();
    assert_eq!(*args.id(), id);
    assert_eq!(*args.reason(), CloseReason::Closed.as_u32());
    assert!(service.state().list.is_empty());

    client
        .close_notification(9999)
        .await
        .expect("a stale id was rejected instead of ignored");

    conn.release_name(BUS_NAME).await.unwrap();
}

#[tokio::test]
#[ignore = "claims org.freedesktop.Notifications; private bus only"]
async fn the_server_answers_for_itself() {
    let _held = NAME.lock().await;
    let (conn, _service) = started("info", Duration::from_millis(7000)).await;
    let client = client().await;

    let capabilities = client.get_capabilities().await.unwrap();
    assert!(capabilities.contains(&"actions".to_owned()));
    assert!(capabilities.contains(&"body".to_owned()));
    assert!(capabilities.contains(&"persistence".to_owned()));
    assert!(
        !capabilities.contains(&"action-icons".to_owned()),
        "claimed a capability Notifications.qml:151 has commented out"
    );
    assert!(!capabilities.contains(&"sound".to_owned()));

    let (name, vendor, _version, spec) = client.get_server_information().await.unwrap();
    assert_eq!(name, "koompi-notifications");
    assert_eq!(vendor, "KOOMPI");
    assert_eq!(spec, "1.2");

    conn.release_name(BUS_NAME).await.unwrap();
}

/// The stop condition as a test: a bus that already has a notification daemon keeps it.
#[tokio::test]
#[ignore = "claims org.freedesktop.Notifications; private bus only"]
async fn the_name_is_never_taken_from_whoever_already_holds_it() {
    let _held = NAME.lock().await;
    let (conn, first) = started("contended", Duration::from_millis(7000)).await;

    let second_bus = Connection::session().await.unwrap();
    let second = NotificationService::serve_on(
        second_bus.clone(),
        config("contended-second", Duration::from_millis(7000)),
    )
    .await
    .unwrap();

    let refused = second.own_name().await.unwrap_err();
    assert!(
        matches!(refused, koompi_service::Error::Unavailable(_)),
        "a second server displaced the first: {refused}"
    );

    // The first one still answers, which is the thing that would have broken.
    let id = client()
        .await
        .notify("app", 0, "", "still here", "", &[], HashMap::new(), 0)
        .await
        .unwrap();
    settle().await;
    assert!(first.state().get(id).is_some());
    assert!(second.state().list.is_empty());

    conn.release_name(BUS_NAME).await.unwrap();
}
