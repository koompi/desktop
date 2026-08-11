//! The server's state: what is on screen, what is in history, and when each stops being
//! either.
//!
//! Two channels, and the difference is the reason this crate exists in the shape it does.
//! The list is `watch` state, last value wins, because a consumer that fell behind wants the
//! history as it is now. An arriving notification and an invoked action are `broadcast`
//! events, because a popup dropped for a newer list state is a notification the user never
//! saw.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use koompi_service::{Error, Result, Service};
use tokio::sync::{broadcast, watch};
use tokio::task::JoinHandle;
use zbus::fdo::{RequestNameFlags, RequestNameReply};
use zbus::object_server::SignalEmitter;
use zbus::Connection;

use crate::hints::Raw;
use crate::model::{pair_actions, CloseReason, Icon, Notification, Timeout};
use crate::server::Server;
use crate::store::Store;
use crate::{Hints, NotificationsConfig};

pub const BUS_NAME: &str = "org.freedesktop.Notifications";
pub const OBJECT_PATH: &str = "/org/freedesktop/Notifications";

const EVENT_CAPACITY: usize = 64;

/// The history, newest last, exactly as the list at `Notifications.qml:79` holds it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NotificationsState {
    pub list: Vec<Notification>,
}

impl NotificationsState {
    pub fn get(&self, id: u32) -> Option<&Notification> {
        self.list.iter().find(|held| held.id == id)
    }

    /// What is on screen right now, which is a strict subset of the history.
    pub fn popups(&self) -> impl Iterator<Item = &Notification> {
        self.list.iter().filter(|held| held.popup)
    }

    /// `replaces_id` updates where the notification already sits rather than moving it to
    /// the end: a progress notification that jumped the list on every percent would drag
    /// the popup with it.
    fn upsert(&mut self, notification: Notification) -> bool {
        match self.list.iter_mut().find(|held| held.id == notification.id) {
            Some(slot) => {
                *slot = notification;
                true
            }
            None => {
                self.list.push(notification);
                false
            }
        }
    }

    fn remove(&mut self, id: u32) -> bool {
        let before = self.list.len();
        self.list.retain(|held| held.id != id);
        self.list.len() != before
    }

    fn hide_popup(&mut self, id: u32) -> bool {
        match self.list.iter_mut().find(|held| held.id == id) {
            Some(slot) if slot.popup => {
                slot.popup = false;
                true
            }
            _ => false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NotificationEvent {
    /// New, or the same id sent again through `replaces_id`. Either way it wants a popup.
    Posted(Box<Notification>),
    Closed {
        id: u32,
        reason: CloseReason,
    },
    ActionInvoked {
        id: u32,
        action: String,
    },
    /// The history could not be written. Surfaced rather than swallowed: it is the user's
    /// only copy, and a consumer that never hears about this shows a history that quietly
    /// stopped being saved.
    HistoryWriteFailed(String),
}

pub struct NotificationService {
    inner: Arc<Inner>,
    rx: watch::Receiver<NotificationsState>,
}

impl Service for NotificationService {
    type State = NotificationsState;

    fn state(&self) -> NotificationsState {
        self.rx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<NotificationsState> {
        self.rx.clone()
    }
}

impl Drop for NotificationService {
    fn drop(&mut self) {
        for (_, timer) in self.inner.timers.lock().expect("timer map").drain() {
            timer.abort();
        }
    }
}

impl NotificationService {
    pub async fn serve(config: NotificationsConfig) -> Result<Self> {
        Self::serve_on(Connection::session().await?, config).await
    }

    /// Exports the interface and loads the history. It does **not** take
    /// `org.freedesktop.Notifications`; see [`NotificationService::own_name`].
    pub async fn serve_on(conn: Connection, config: NotificationsConfig) -> Result<Self> {
        let store = Store::new(config.history_path.clone());
        let list = store.load()?;
        let next = list.iter().map(|held| held.id).max().unwrap_or(0) + 1;

        let (tx, rx) = watch::channel(NotificationsState { list });
        let (events, _) = broadcast::channel(EVENT_CAPACITY);
        let inner = Arc::new(Inner {
            conn: conn.clone(),
            config,
            store,
            tx,
            events,
            next_id: AtomicU32::new(next),
            timers: Mutex::new(HashMap::new()),
        });

        conn.object_server()
            .at(
                OBJECT_PATH,
                Server {
                    inner: Arc::clone(&inner),
                },
            )
            .await?;

        Ok(Self { inner, rx })
    }

    /// Claims the well-known name, which is the one call in this crate that can silence a
    /// desktop.
    ///
    /// It asks without `ReplaceExisting` and with `DoNotQueue`, so a bus that already has a
    /// notification daemon gets an error here rather than a new one: displacing the owner
    /// takes every notification away from the running shell, and queueing behind it does the
    /// same thing later, at a moment nobody chose.
    pub async fn own_name(&self) -> Result<()> {
        let taken =
            || Error::Unavailable(format!("{BUS_NAME}: another process on this bus owns it"));

        // `DoNotQueue` turns a contended name into an error rather than a reply, so the case
        // this whole method exists for arrives on the other arm.
        let reply = match self
            .inner
            .conn
            .request_name_with_flags(
                BUS_NAME,
                RequestNameFlags::AllowReplacement | RequestNameFlags::DoNotQueue,
            )
            .await
        {
            Ok(reply) => reply,
            Err(zbus::Error::NameTaken) => return Err(taken()),
            Err(error) => return Err(Error::Bus(error)),
        };

        match reply {
            RequestNameReply::PrimaryOwner | RequestNameReply::AlreadyOwner => Ok(()),
            _ => Err(taken()),
        }
    }

    /// Arrivals, closures and action invocations, none of which may be dropped.
    pub fn events(&self) -> broadcast::Receiver<NotificationEvent> {
        self.inner.events.subscribe()
    }

    pub fn history_path(&self) -> &std::path::Path {
        self.inner.store.path()
    }

    /// The user dismissed it, or a consumer decided it is done with.
    pub async fn close(&self, id: u32, reason: CloseReason) -> bool {
        self.inner.close(id, reason).await
    }

    pub async fn close_all(&self, reason: CloseReason) {
        let ids: Vec<u32> = self.rx.borrow().list.iter().map(|held| held.id).collect();
        for id in ids {
            self.inner.close(id, reason).await;
        }
    }

    /// The user picked one of the notification's actions.
    ///
    /// The sender hears `ActionInvoked`, and unless it asked to be `resident` the
    /// notification is then closed, which is what `Notifications.qml:239-253` does.
    pub async fn invoke_action(&self, id: u32, action: &str) -> Result<()> {
        self.inner.invoke_action(id, action).await
    }
}

pub(crate) struct Inner {
    conn: Connection,
    pub(crate) config: NotificationsConfig,
    store: Store,
    tx: watch::Sender<NotificationsState>,
    events: broadcast::Sender<NotificationEvent>,
    next_id: AtomicU32,
    timers: Mutex<HashMap<u32, JoinHandle<()>>>,
}

impl Inner {
    #[allow(clippy::too_many_arguments)]
    pub(crate) async fn notify(
        self: &Arc<Self>,
        app_name: String,
        replaces_id: u32,
        app_icon: String,
        summary: String,
        body: String,
        actions: &[String],
        hints: &Raw,
        expire_timeout: i32,
    ) -> u32 {
        let id = if replaces_id == 0 {
            self.next_id.fetch_add(1, Ordering::SeqCst)
        } else {
            // An application may name an id we have never issued; the spec still says the
            // reply is that id. Keeping the counter above it stops the next new
            // notification colliding with it.
            self.next_id.fetch_max(replaces_id + 1, Ordering::SeqCst);
            replaces_id
        };

        let notification = Notification {
            id,
            app_name,
            app_icon: Icon::parse(&app_icon),
            summary,
            body,
            actions: pair_actions(actions),
            hints: Hints::decode(hints),
            timeout: Timeout::from(expire_timeout),
            time: now_millis(),
            popup: true,
        };

        self.cancel_timer(id);
        self.tx.send_if_modified(|state| {
            state.upsert(notification.clone());
            true
        });
        self.persist().await;
        let _ = self
            .events
            .send(NotificationEvent::Posted(Box::new(notification)));
        self.schedule_expiry(id, expire_timeout.into());
        id
    }

    /// Gone from the history and off the screen, and the sender is told which of the spec's
    /// reasons it was.
    pub(crate) async fn close(&self, id: u32, reason: CloseReason) -> bool {
        self.cancel_timer(id);
        if !self.tx.send_if_modified(|state| state.remove(id)) {
            return false;
        }
        self.persist().await;
        self.announce_closed(id, reason).await;
        true
    }

    /// The popup's time is up. The entry stays in the list, because the list is the history
    /// panel and `Notifications.qml:223-228` keeps it there too; only a `transient` sender
    /// asked not to be remembered.
    async fn expire(&self, id: u32) {
        let transient = self
            .tx
            .borrow()
            .get(id)
            .is_some_and(|held| held.hints.transient);

        let changed = if transient {
            self.tx.send_if_modified(|state| state.remove(id))
        } else {
            self.tx.send_if_modified(|state| state.hide_popup(id))
        };
        if !changed {
            return;
        }

        self.persist().await;
        self.announce_closed(id, CloseReason::Expired).await;
    }

    async fn invoke_action(&self, id: u32, action: &str) -> Result<()> {
        let resident = {
            let state = self.tx.borrow();
            let notification = state
                .get(id)
                .ok_or_else(|| Error::Unavailable(format!("notification {id}")))?;
            notification.action(action).ok_or_else(|| {
                Error::Unavailable(format!("action {action:?} on notification {id}"))
            })?;
            notification.hints.resident
        };

        Server::action_invoked(&self.emitter()?, id, action).await?;
        let _ = self.events.send(NotificationEvent::ActionInvoked {
            id,
            action: action.to_owned(),
        });

        if !resident {
            self.close(id, CloseReason::Dismissed).await;
        }
        Ok(())
    }

    async fn announce_closed(&self, id: u32, reason: CloseReason) {
        if let Ok(emitter) = self.emitter() {
            let _ = Server::notification_closed(&emitter, id, reason.as_u32()).await;
        }
        let _ = self.events.send(NotificationEvent::Closed { id, reason });
    }

    fn emitter(&self) -> Result<SignalEmitter<'static>> {
        Ok(SignalEmitter::new(&self.conn, OBJECT_PATH)?)
    }

    /// The state goes out before the event that explains it, so a consumer woken by the
    /// event finds the list already saying the same thing.
    async fn persist(&self) {
        let list = self.tx.borrow().list.clone();
        if let Err(error) = self.store.save(&list).await {
            let _ = self
                .events
                .send(NotificationEvent::HistoryWriteFailed(error.to_string()));
        }
    }

    fn schedule_expiry(self: &Arc<Self>, id: u32, timeout: Timeout) {
        let Some(delay) = expiry_delay(&self.config, timeout) else {
            return;
        };

        let inner = Arc::clone(self);
        let timer = tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            inner.expire(id).await;
        });

        let mut timers = self.timers.lock().expect("timer map");
        // A fired timer leaves its handle behind, and nothing else ever collects them.
        timers.retain(|_, held| !held.is_finished());
        if let Some(replaced) = timers.insert(id, timer) {
            replaced.abort();
        }
    }

    fn cancel_timer(&self, id: u32) {
        if let Some(timer) = self.timers.lock().expect("timer map").remove(&id) {
            timer.abort();
        }
    }
}

/// `-1` takes the shell's default and is stretched by the power-saving multiplier like every
/// other interval. A timeout the sender named is its decision, not ours, and is left alone.
fn expiry_delay(config: &NotificationsConfig, timeout: Timeout) -> Option<Duration> {
    match timeout {
        Timeout::Never => None,
        Timeout::ServerDefault => Some(config.poll_rate.interval(config.default_timeout)),
        Timeout::Millis(millis) => Some(Duration::from_millis(u64::from(millis))),
    }
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|since| since.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Action;
    use koompi_service::PollRate;

    fn notification(id: u32, summary: &str) -> Notification {
        Notification {
            id,
            app_name: "notify-send".into(),
            app_icon: Icon::Empty,
            summary: summary.to_owned(),
            body: String::new(),
            actions: vec![Action {
                identifier: "yes".into(),
                text: "Yes".into(),
            }],
            hints: Hints::default(),
            timeout: Timeout::ServerDefault,
            time: 1786266932702,
            popup: true,
        }
    }

    #[test]
    fn replaces_id_edits_in_place_and_leaves_the_list_one_long() {
        let mut state = NotificationsState::default();
        assert!(!state.upsert(notification(1, "first")));
        assert!(!state.upsert(notification(2, "second")));

        assert!(state.upsert(notification(1, "first, edited")));

        assert_eq!(state.list.len(), 2);
        assert_eq!(state.list[0].summary, "first, edited");
        assert_eq!(state.list[1].summary, "second", "the order moved");
        assert_eq!(state.get(1).unwrap().summary, "first, edited");
    }

    #[test]
    fn an_expired_popup_leaves_the_history_entry_behind() {
        let mut state = NotificationsState::default();
        state.upsert(notification(1, "kept"));

        assert!(state.hide_popup(1));
        assert_eq!(state.list.len(), 1, "expiry deleted the user's history");
        assert_eq!(state.popups().count(), 0);
        assert!(!state.hide_popup(1), "hiding twice reported a change");
        assert!(!state.hide_popup(99));

        assert!(state.remove(1));
        assert!(!state.remove(1));
        assert!(state.list.is_empty());
    }

    /// `PowerSaving.qml:33` reaches the popup life as it reaches every other interval, and
    /// stops at the boundary where the sender said what it wanted.
    #[test]
    fn the_server_default_scales_with_the_poll_rate_and_a_named_timeout_does_not() {
        let delay = |rate, timeout| {
            expiry_delay(
                &NotificationsConfig {
                    poll_rate: rate,
                    ..NotificationsConfig::default()
                },
                timeout,
            )
        };

        assert_eq!(
            delay(PollRate::NORMAL, Timeout::ServerDefault),
            Some(Duration::from_millis(7000))
        );
        assert_eq!(
            delay(PollRate::SAVING, Timeout::ServerDefault),
            Some(Duration::from_millis(14000))
        );
        assert_eq!(
            delay(PollRate::SAVING, Timeout::Millis(2500)),
            Some(Duration::from_millis(2500))
        );
        assert_eq!(delay(PollRate::NORMAL, Timeout::Never), None);
    }
}
