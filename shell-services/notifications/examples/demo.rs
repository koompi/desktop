//! The server, running, printing everything it decodes.
//!
//! ```text
//! dbus-run-session -- cargo run -p koompi-notifications --example demo [history.json]
//! cargo run -p koompi-notifications --example demo -- read <history.json>
//! ```
//!
//! Two safeguards, both about not damaging the seat this runs on.
//!
//! It refuses to take `org.freedesktop.Notifications` on a bus that has anything else on it,
//! which on this machine means the session bus where Quickshell owns the name: a second
//! owner there and the user stops seeing notifications entirely. Run it under
//! `dbus-run-session`.
//!
//! And it writes its history to a scratch file unless told otherwise, because the file at
//! `Directories.qml:36` is the user's only copy. `read` is the mode that points at the real
//! one: it parses and prints it and writes nothing.

use std::path::PathBuf;
use std::time::Instant;

use koompi_notifications::{
    CloseReason, Hints, Notification, NotificationEvent, NotificationService, NotificationsConfig,
    Store, BUS_NAME,
};
use koompi_service::Service;
use zbus::Connection;

const CONTROL_NAME: &str = "org.koompi.NotificationsDemo";
const CONTROL_PATH: &str = "/org/koompi/NotificationsDemo";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>()[..] {
        ["read", path] => read(PathBuf::from(path)),
        [] => serve(scratch_history()).await,
        [path] => serve(PathBuf::from(path)).await,
        _ => {
            eprintln!("usage: demo [history.json] | demo read <history.json>");
            std::process::exit(2);
        }
    }
}

/// Parses a history and prints it. Nothing here opens the file for writing, which is what
/// makes it safe to point at the live one.
fn read(path: PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    let store = Store::new(&path);
    let list = store.load()?;
    println!("{} parsed, {} entry(s)\n", path.display(), list.len());
    for notification in &list {
        print_notification(notification);
    }
    Ok(())
}

async fn serve(history: PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    let conn = Connection::session().await?;
    refuse_a_shared_bus(&conn).await?;

    let config = NotificationsConfig {
        history_path: history,
        ..NotificationsConfig::default()
    };
    println!("default timeout  {:?}", config.default_timeout);
    println!("capabilities     {}", config.capabilities.join(", "));

    let service = NotificationService::serve_on(conn.clone(), config).await?;
    println!("history          {}", service.history_path().display());

    let state = service.state();
    println!("restored         {} entry(s)", state.list.len());
    for notification in &state.list {
        print_notification(notification);
    }

    service.own_name().await?;
    println!("\nserving {BUS_NAME} as {}", conn.unique_name().unwrap());

    let control = Control {
        service: std::sync::Arc::new(service),
    };
    let service = control.service.clone();
    conn.object_server().at(CONTROL_PATH, control).await?;
    conn.request_name(CONTROL_NAME).await?;

    // --address, not --user: `busctl --user` goes to the seat's own bus whatever
    // DBUS_SESSION_BUS_ADDRESS says, which is the bus this must never touch.
    println!(
        "invoke an action with:\n  \
         busctl --address=\"$DBUS_SESSION_BUS_ADDRESS\" call {CONTROL_NAME} {CONTROL_PATH} {CONTROL_NAME} InvokeAction us <id> <action>\n  \
         busctl --address=\"$DBUS_SESSION_BUS_ADDRESS\" call {CONTROL_NAME} {CONTROL_PATH} {CONTROL_NAME} Close u <id>"
    );

    println!("\n-- following, ^C to stop --");
    let started = Instant::now();
    let mut events = service.events();
    let mut changes = service.subscribe();

    loop {
        tokio::select! {
            changed = changes.changed() => {
                if changed.is_err() {
                    return Ok(());
                }
                let state = changes.borrow_and_update().clone();
                println!(
                    "[{:>7.3}s] list {} entry(s), {} popup(s): {:?}",
                    started.elapsed().as_secs_f64(),
                    state.list.len(),
                    state.popups().count(),
                    state.list.iter().map(|held| held.id).collect::<Vec<_>>()
                );
            }
            event = events.recv() => {
                match event {
                    Ok(NotificationEvent::Posted(notification)) => {
                        println!(
                            "[{:>7.3}s] posted",
                            started.elapsed().as_secs_f64()
                        );
                        print_notification(&notification);
                    }
                    Ok(NotificationEvent::Closed { id, reason }) => println!(
                        "[{:>7.3}s] closed {id}, reason {} ({reason:?})",
                        started.elapsed().as_secs_f64(),
                        reason.as_u32()
                    ),
                    Ok(NotificationEvent::ActionInvoked { id, action }) => println!(
                        "[{:>7.3}s] action invoked on {id}: {action}",
                        started.elapsed().as_secs_f64()
                    ),
                    Ok(NotificationEvent::HistoryWriteFailed(error)) => println!(
                        "[{:>7.3}s] HISTORY NOT WRITTEN: {error}",
                        started.elapsed().as_secs_f64()
                    ),
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => return Ok(()),
                    Err(lagged) => println!("[events] {lagged}"),
                }
            }
        }
    }
}

/// The stop condition, enforced rather than documented. A bus from `dbus-run-session` has
/// exactly one well-known name on it; the session bus on a running seat has dozens, and one
/// of them is the notification daemon the user is looking at.
async fn refuse_a_shared_bus(conn: &Connection) -> Result<(), Box<dyn std::error::Error>> {
    let names = zbus::fdo::DBusProxy::new(conn).await?.list_names().await?;
    let well_known: Vec<String> = names
        .iter()
        .map(|name| name.to_string())
        .filter(|name| !name.starts_with(':'))
        .collect();

    if well_known != ["org.freedesktop.DBus"] {
        return Err(format!(
            "this bus is shared with {} other name(s), and taking {BUS_NAME} on it would \
             silence the running desktop. Run under dbus-run-session.",
            well_known.len() - 1
        )
        .into());
    }
    Ok(())
}

/// Only the demo exports this. The library's action invocation is a Rust call, because the
/// consumer that knows a user clicked something is in-process with it; this exists so the
/// same path can be driven from `busctl` in another pane.
struct Control {
    service: std::sync::Arc<NotificationService>,
}

#[zbus::interface(name = "org.koompi.NotificationsDemo")]
impl Control {
    async fn invoke_action(&self, id: u32, action: String) -> zbus::fdo::Result<()> {
        self.service
            .invoke_action(id, &action)
            .await
            .map_err(|error| zbus::fdo::Error::Failed(error.to_string()))
    }

    async fn close(&self, id: u32) -> bool {
        self.service.close(id, CloseReason::Dismissed).await
    }
}

/// Enough of the buffer to see that it is the sender's, byte for byte, without a hashing
/// dependency to say the same thing.
fn hex<'b>(bytes: impl Iterator<Item = &'b u8>) -> String {
    bytes
        .map(|byte| format!("{byte:02x}"))
        .collect::<Vec<_>>()
        .join(" ")
}

fn scratch_history() -> PathBuf {
    PathBuf::from("/tmp/j07-notifications/demo-history.json")
}

fn print_notification(notification: &Notification) {
    println!("\n  id             {}", notification.id);
    println!("  app_name       {:?}", notification.app_name);
    println!("  app_icon       {:?}", notification.app_icon);
    println!("  summary        {:?}", notification.summary);
    println!("  body           {:?}", notification.body);
    println!("  timeout        {:?}", notification.timeout);
    println!("  time           {}", notification.time);
    println!("  popup          {}", notification.popup);
    if notification.actions.is_empty() {
        println!("  actions        <none>");
    }
    for action in &notification.actions {
        println!(
            "  action         {:?} -> {:?}",
            action.identifier, action.text
        );
    }
    print_hints(&notification.hints);
}

fn print_hints(hints: &Hints) {
    println!(
        "  urgency        {:?} ({})",
        hints.urgency,
        hints.urgency.as_u8()
    );
    match &hints.image {
        // Dimensions and a byte count. The bytes stay raw, which is this crate's whole
        // image policy.
        Some(image) => {
            println!(
                "  image-data     {}x{}, rowstride {}, {} channel(s), {} bits/sample, alpha {}, {} bytes raw",
                image.width,
                image.height,
                image.rowstride,
                image.channels,
                image.bits_per_sample,
                image.has_alpha,
                image.bytes.len()
            );
            println!(
                "  image bytes    first 8 {}, last 8 {}",
                hex(image.bytes.iter().take(8)),
                hex(image
                    .bytes
                    .iter()
                    .rev()
                    .take(8)
                    .collect::<Vec<_>>()
                    .into_iter()
                    .rev())
            );
        }
        None => println!("  image-data     <none>"),
    }
    println!("  image-path     {:?}", hints.image_path);
    println!("  desktop-entry  {:?}", hints.desktop_entry);
    println!("  category       {:?}", hints.category);
    println!("  transient      {}", hints.transient);
    println!("  resident       {}", hints.resident);
    println!("  value          {:?}", hints.value);
    if hints.other.is_empty() {
        println!("  other hints    <none>");
    }
    for (key, rendering) in &hints.other {
        println!("  other hint     {key} = {rendering}");
    }
}
