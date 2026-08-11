//! Host mode: what `Quickshell.Services.SystemTray` is behind `TrayService.qml:6`.
//!
//! It does not own `org.kde.StatusNotifierWatcher`. It registers with whoever does, reads
//! the item list out of it and proxies each item, which is why it can run beside the shell
//! that owns the tray on this seat without taking anything from it.

use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use futures_util::stream::{BoxStream, SelectAll, StreamExt};
use koompi_service::{drain, Backoff, Error, Result, Service};
use tokio::sync::{broadcast, watch};
use tokio::task::JoinHandle;
use zbus::fdo::{DBusProxy, PropertiesProxy};
use zbus::message::Message;
use zbus::names::InterfaceName;
use zbus::proxy::CacheProperties;
use zbus::{Connection, MatchRule, MessageStream};

use crate::item::{ItemAddress, TrayItem};
use crate::menu::{self, MenuItem};
use crate::proxy::{StatusNotifierItemProxy, StatusNotifierWatcherProxy};
use crate::watcher::WATCHER_NAME;
use crate::TrayConfig;

const ITEM: &str = "org.kde.StatusNotifierItem";
const ITEM_IFACE: InterfaceName<'static> = InterfaceName::from_static_str_unchecked(ITEM);

const EVENT_CAPACITY: usize = 64;

/// The tray as it is now. `TrayService.qml:12-18` filters and pins on top of this; which
/// items a user sees is config, and config is not tray state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrayState {
    pub items: Vec<TrayItem>,
    /// False when nothing owns `org.kde.StatusNotifierWatcher`. A seat with no watcher is
    /// not a broken tray, it is a tray nobody is keeping, and it draws differently from a
    /// watcher that answered with no items.
    pub watcher_present: bool,
}

impl TrayState {
    pub fn item(&self, key: &str) -> Option<&TrayItem> {
        self.items.iter().find(|item| item.key() == key)
    }
}

/// What must not be missed. State is last-value-wins on a `watch`, but an application
/// asking for its menu to be opened is a thing that happened, and a later state change
/// does not supersede it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TrayEvent {
    ItemRegistered(String),
    ItemUnregistered(String),
    /// `com.canonical.dbusmenu` `ItemActivationRequested`: the application wants this
    /// entry acted on, without the user having touched the panel.
    MenuActivationRequested {
        item: String,
        id: i32,
        timestamp: u32,
    },
    /// The application rebuilt part of its menu; a tree read before this is stale.
    MenuLayoutUpdated {
        item: String,
        revision: u32,
        parent: i32,
    },
}

pub struct TrayService {
    ctx: Arc<Ctx>,
    rx: watch::Receiver<TrayState>,
    events: broadcast::Sender<TrayEvent>,
    task: JoinHandle<()>,
}

impl Service for TrayService {
    type State = TrayState;

    fn state(&self) -> TrayState {
        self.rx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<TrayState> {
        self.rx.clone()
    }
}

impl Drop for TrayService {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl TrayService {
    pub async fn connect(config: TrayConfig) -> Result<Self> {
        Self::with_connection(Connection::session().await?, config).await
    }

    pub async fn with_connection(conn: Connection, config: TrayConfig) -> Result<Self> {
        let ctx = Arc::new(Ctx { conn, config });
        let present = ctx.register_host().await.is_ok();
        let items = if present {
            read_items(&ctx).await.unwrap_or_default()
        } else {
            Vec::new()
        };

        let (tx, rx) = watch::channel(TrayState {
            items,
            watcher_present: present,
        });
        let (events, _) = broadcast::channel(EVENT_CAPACITY);
        let task = tokio::spawn(run(Arc::clone(&ctx), tx, events.clone()));

        Ok(Self {
            ctx,
            rx,
            events,
            task,
        })
    }

    /// Registrations and menu activations, none of which may be dropped.
    pub fn events(&self) -> broadcast::Receiver<TrayEvent> {
        self.events.subscribe()
    }

    pub fn item(&self, key: &str) -> Option<TrayItem> {
        self.rx.borrow().item(key).cloned()
    }

    pub async fn activate(&self, key: &str, x: i32, y: i32) -> Result<()> {
        self.item_proxy(key).await?.activate(x, y).await?;
        Ok(())
    }

    pub async fn secondary_activate(&self, key: &str, x: i32, y: i32) -> Result<()> {
        self.item_proxy(key).await?.secondary_activate(x, y).await?;
        Ok(())
    }

    pub async fn context_menu(&self, key: &str, x: i32, y: i32) -> Result<()> {
        self.item_proxy(key).await?.context_menu(x, y).await?;
        Ok(())
    }

    /// `orientation` is "vertical" or "horizontal", as the spec words it.
    pub async fn scroll(&self, key: &str, delta: i32, orientation: &str) -> Result<()> {
        self.item_proxy(key).await?.scroll(delta, orientation).await?;
        Ok(())
    }

    /// The whole menu, `AboutToShow` first so lazily built applications have settled.
    pub async fn menu(&self, key: &str) -> Result<MenuItem> {
        let (service, path) = self.menu_source(key)?;
        menu::layout(&self.ctx.conn, &service, &path, 0).await
    }

    /// One subtree, for a submenu that reported no children until it was asked.
    pub async fn submenu(&self, key: &str, id: i32) -> Result<MenuItem> {
        let (service, path) = self.menu_source(key)?;
        menu::layout(&self.ctx.conn, &service, &path, id).await
    }

    pub async fn about_to_show(&self, key: &str, id: i32) -> Result<bool> {
        let (service, path) = self.menu_source(key)?;
        menu::about_to_show(&self.ctx.conn, &service, &path, id).await
    }

    /// The one menu call an application acts on. Nothing in this crate sends it by itself.
    pub async fn click(&self, key: &str, id: i32) -> Result<()> {
        self.menu_event(key, id, "clicked").await
    }

    pub async fn menu_event(&self, key: &str, id: i32, kind: &str) -> Result<()> {
        let (service, path) = self.menu_source(key)?;
        menu::event(&self.ctx.conn, &service, &path, id, kind, now()).await
    }

    fn address(&self, key: &str) -> Result<ItemAddress> {
        self.rx
            .borrow()
            .item(key)
            .map(|item| item.address.clone())
            .ok_or_else(|| Error::Unavailable(format!("tray item {key}")))
    }

    fn menu_source(&self, key: &str) -> Result<(String, String)> {
        let state = self.rx.borrow();
        let item = state
            .item(key)
            .ok_or_else(|| Error::Unavailable(format!("tray item {key}")))?;
        let menu = item
            .menu
            .clone()
            .ok_or_else(|| Error::Unavailable(format!("a menu on {key}")))?;
        Ok((item.address.service.clone(), menu))
    }

    async fn item_proxy(&self, key: &str) -> Result<StatusNotifierItemProxy<'_>> {
        let address = self.address(key)?;
        Ok(StatusNotifierItemProxy::builder(&self.ctx.conn)
            .destination(address.service)?
            .path(address.path)?
            .build()
            .await?)
    }
}

fn now() -> u32 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|since| since.as_secs() as u32)
        .unwrap_or(0)
}

struct Ctx {
    conn: Connection,
    config: TrayConfig,
}

impl Ctx {
    async fn watcher(&self) -> Result<StatusNotifierWatcherProxy<'_>> {
        Ok(StatusNotifierWatcherProxy::builder(&self.conn)
            .cache_properties(CacheProperties::No)
            .build()
            .await?)
    }

    /// Announced once per watcher, never per refresh: a watcher that echoes
    /// `StatusNotifierHostRegistered` back at us would otherwise have us answer it with
    /// another registration.
    async fn register_host(&self) -> Result<()> {
        let me = self
            .conn
            .unique_name()
            .ok_or_else(|| Error::Protocol("connection has no unique name".into()))?
            .to_string();
        self.watcher().await?.register_status_notifier_host(&me).await?;
        Ok(())
    }
}

async fn read_items(ctx: &Ctx) -> Result<Vec<TrayItem>> {
    let registered = ctx.watcher().await?.registered_status_notifier_items().await?;

    let mut items = Vec::with_capacity(registered.len());
    for entry in registered {
        let Some(address) = ItemAddress::parse(&entry) else {
            continue;
        };
        // An item that exited between the watcher's list and our read is not an error,
        // and the watcher's own unregistration is already on its way to us.
        if let Ok(item) = read_item(ctx, address).await {
            items.push(item);
        }
    }
    Ok(items)
}

async fn read_item(ctx: &Ctx, address: ItemAddress) -> Result<TrayItem> {
    let owner = owner_of(ctx, &address.service).await;
    let props = PropertiesProxy::builder(&ctx.conn)
        .destination(address.service.clone())?
        .path(address.path.clone())?
        .cache_properties(CacheProperties::No)
        .build()
        .await?
        .get_all(ITEM_IFACE)
        .await
        .map_err(|error| Error::Bus(error.into()))?;

    if props.is_empty() {
        return Err(Error::Protocol(format!(
            "{} exports no StatusNotifierItem properties",
            address.key()
        )));
    }
    Ok(TrayItem::from_props(address, owner, &props))
}

/// Signals carry the unique name, so an item registered under a well-known one has to be
/// resolved once to be recognised when it changes.
async fn owner_of(ctx: &Ctx, service: &str) -> String {
    if service.starts_with(':') {
        return service.to_owned();
    }
    let Ok(proxy) = DBusProxy::new(&ctx.conn).await else {
        return service.to_owned();
    };
    match zbus::names::BusName::try_from(service) {
        Ok(name) => proxy
            .get_name_owner(name)
            .await
            .map(|owner| owner.to_string())
            .unwrap_or_else(|_| service.to_owned()),
        Err(_) => service.to_owned(),
    }
}

enum Wake {
    /// The set of items may have moved.
    Items,
    /// One item said something changed; the payload is its unique name.
    Item(String),
    Menu(Message),
    WatcherOwner(bool),
}

async fn run(
    ctx: Arc<Ctx>,
    tx: watch::Sender<TrayState>,
    events: broadcast::Sender<TrayEvent>,
) {
    let Ok(mut wake) = wake_stream(&ctx).await else {
        return;
    };

    // No poll lives here; this is the wait before retrying a watcher that is not
    // answering, and `PowerSaving.qml:33` stretches it like every other timer.
    let rate = ctx.config.poll_rate;
    let mut backoff = Backoff::new(
        rate.interval(Duration::from_millis(250)),
        rate.interval(Duration::from_secs(30)),
    );
    let mut offline = !tx.borrow().watcher_present;

    loop {
        if offline {
            backoff.wait().await;
            if ctx.register_host().await.is_err() {
                continue;
            }
        } else {
            match wake.next().await {
                None => return,
                Some(Wake::Item(owner)) => {
                    refresh_item(&ctx, &tx, &owner).await;
                    continue;
                }
                Some(Wake::Menu(message)) => {
                    publish_menu_event(&tx, &events, &message);
                    continue;
                }
                Some(Wake::WatcherOwner(present)) => {
                    if !present {
                        publish(&tx, &events, Vec::new(), false);
                        offline = true;
                        continue;
                    }
                    // A watcher that just appeared has never heard of us.
                    if ctx.register_host().await.is_err() {
                        offline = true;
                        continue;
                    }
                }
                Some(Wake::Items) => {}
            }
        }

        match read_items(&ctx).await {
            Ok(items) => {
                offline = false;
                backoff.reset();
                publish(&tx, &events, items, true);
            }
            Err(_) => offline = true,
        }
    }
}

/// Sends the state, and the registrations that got it there, in that order: a consumer
/// woken by an event must find the item already in the state it reads next.
fn publish(
    tx: &watch::Sender<TrayState>,
    events: &broadcast::Sender<TrayEvent>,
    items: Vec<TrayItem>,
    watcher_present: bool,
) {
    let gone: Vec<String> = tx
        .borrow()
        .items
        .iter()
        .map(TrayItem::key)
        .filter(|key| !items.iter().any(|item| &item.key() == key))
        .collect();
    let arrived: Vec<String> = items
        .iter()
        .map(TrayItem::key)
        .filter(|key| !tx.borrow().items.iter().any(|item| &item.key() == key))
        .collect();

    let state = TrayState {
        items,
        watcher_present,
    };
    tx.send_if_modified(|current| {
        let changed = *current != state;
        if changed {
            *current = state;
        }
        changed
    });

    for key in gone {
        let _ = events.send(TrayEvent::ItemUnregistered(key));
    }
    for key in arrived {
        let _ = events.send(TrayEvent::ItemRegistered(key));
    }
}

async fn refresh_item(ctx: &Ctx, tx: &watch::Sender<TrayState>, owner: &str) {
    let Some(address) = tx
        .borrow()
        .items
        .iter()
        .find(|item| item.owner == owner)
        .map(|item| item.address.clone())
    else {
        return;
    };
    let Ok(item) = read_item(ctx, address).await else {
        return;
    };

    tx.send_if_modified(|state| {
        let Some(slot) = state.items.iter_mut().find(|held| held.owner == owner) else {
            return false;
        };
        if *slot == item {
            return false;
        }
        *slot = item;
        true
    });
}

fn publish_menu_event(
    tx: &watch::Sender<TrayState>,
    events: &broadcast::Sender<TrayEvent>,
    message: &Message,
) {
    let header = message.header();
    let (Some(sender), Some(member), Some(path)) =
        (header.sender(), header.member(), header.path())
    else {
        return;
    };

    let sender = sender.to_string();
    let path = path.to_string();
    let Some(item) = tx.borrow().items.iter().find_map(|held| {
        (held.owner == sender && held.menu.as_deref() == Some(path.as_str())).then(|| held.key())
    }) else {
        return;
    };

    let event = match member.as_str() {
        "ItemActivationRequested" => message
            .body()
            .deserialize::<(i32, u32)>()
            .ok()
            .map(|(id, timestamp)| TrayEvent::MenuActivationRequested {
                item,
                id,
                timestamp,
            }),
        "LayoutUpdated" => message
            .body()
            .deserialize::<(u32, i32)>()
            .ok()
            .map(|(revision, parent)| TrayEvent::MenuLayoutUpdated {
                item,
                revision,
                parent,
            }),
        _ => None,
    };

    if let Some(event) = event {
        let _ = events.send(event);
    }
}

/// One rule per kind of change rather than one subscription per item, so an item that
/// appears after start needs nothing added.
async fn wake_stream(ctx: &Ctx) -> Result<SelectAll<BoxStream<'static, Wake>>> {
    let watcher = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(WATCHER_NAME)?
        .build();

    let items = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface(ITEM_IFACE)?
        .build();

    // Ayatana's items answer with PropertiesChanged where KDE's send NewIcon.
    let item_props = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .arg(0, ITEM)?
        .build();

    let menus = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface(crate::menu::IFACE)?
        .build();

    let owner = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.DBus")?
        .member("NameOwnerChanged")?
        .arg(0, WATCHER_NAME)?
        .build();

    let sender_of = |message: &Message| {
        message
            .header()
            .sender()
            .map(|sender| sender.to_string())
            .unwrap_or_default()
    };

    let streams: Vec<BoxStream<'static, Wake>> = vec![
        stream(ctx, watcher, |_| Some(Wake::Items)).await?,
        stream(ctx, items, move |message| {
            Some(Wake::Item(sender_of(&message)))
        })
        .await?,
        stream(ctx, item_props, move |message| {
            Some(Wake::Item(sender_of(&message)))
        })
        .await?,
        stream(ctx, menus, |message| Some(Wake::Menu(message))).await?,
        stream(ctx, owner, |message| {
            let taken = message
                .body()
                .deserialize::<(String, String, String)>()
                .map(|(_, _, new_owner)| !new_owner.is_empty())
                .unwrap_or(false);
            Some(Wake::WatcherOwner(taken))
        })
        .await?,
    ];

    Ok(futures_util::stream::select_all(streams))
}

/// Drained on a task of its own. The loop awaits `read_items` and `refresh_item` on this
/// same connection, and a desktop coming up registers every tray item it has at once:
/// see [`koompi_service::drain`].
async fn stream<T, F>(
    ctx: &Ctx,
    rule: MatchRule<'static>,
    classify: F,
) -> Result<BoxStream<'static, T>>
where
    T: Send + 'static,
    F: FnMut(Message) -> Option<T> + Send + 'static,
{
    let stream = MessageStream::for_match_rule(rule, &ctx.conn, Some(32)).await?;
    Ok(drain(stream, classify).boxed())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::item::Props;
    use zvariant::{OwnedValue, Value};

    /// The loop awaits `read_items`, which is a `GetAll` per item on the connection the
    /// wake streams are on. A desktop session coming up registers every tray item it has
    /// at once, and each one then announces its icon. The wedge is silent: `read_items`
    /// never returns, so the tray stops at whatever it had and nothing retries.
    #[tokio::test]
    async fn a_burst_from_the_items_does_not_wedge_the_read_the_loop_is_waiting_on() {
        let (them, ours) = koompi_service::testing::peers().await;
        let ctx = Ctx {
            conn: ours.clone(),
            config: TrayConfig::default(),
        };
        let mut wake = wake_stream(&ctx).await.unwrap();

        let peer = tokio::spawn(async move {
            let peer = koompi_service::testing::listen(them).await;
            for _ in 0..512 {
                peer.conn()
                    .emit_signal(None::<()>, "/StatusNotifierItem", ITEM, "NewIcon", &())
                    .await
                    .unwrap();
            }
            peer.answer_one_call().await;
        });

        // the loop is inside `read_items` here, not touching its wake streams
        koompi_service::testing::ping(&ours).await;
        peer.await.unwrap();

        // one per signal off the item rule, and one more off the watcher rule, whose
        // sender only a bus daemon can resolve
        let mut woken = 0;
        while wake.next().await.is_some() {
            woken += 1;
            if woken == 1024 {
                break;
            }
        }
        assert_eq!(woken, 1024, "the burst was dropped, not drained");
    }

    fn item(service: &str, id: &str) -> TrayItem {
        let props: Props = [("Id", Value::from(id))]
            .into_iter()
            .map(|(k, v)| (k.to_owned(), OwnedValue::try_from(v).unwrap()))
            .collect();
        TrayItem::from_props(
            ItemAddress::parse(&format!("{service}/StatusNotifierItem")).unwrap(),
            service.to_owned(),
            &props,
        )
    }

    /// A click that arrives while the panel is redrawing must survive; a stale item list
    /// must not. That is the whole reason the two channels are different kinds.
    #[tokio::test]
    async fn registrations_reach_a_subscriber_that_was_behind_the_state() {
        let (tx, _rx) = watch::channel(TrayState {
            items: vec![item(":1.1", "old")],
            watcher_present: true,
        });
        let (events, mut rx_events) = broadcast::channel(EVENT_CAPACITY);

        publish(&tx, &events, vec![item(":1.2", "new")], true);

        assert_eq!(
            rx_events.recv().await.unwrap(),
            TrayEvent::ItemUnregistered(":1.1/StatusNotifierItem".into())
        );
        assert_eq!(
            rx_events.recv().await.unwrap(),
            TrayEvent::ItemRegistered(":1.2/StatusNotifierItem".into())
        );
        assert_eq!(tx.borrow().items.len(), 1);
        assert_eq!(tx.borrow().items[0].id, "new");
    }

    #[test]
    fn republishing_the_same_items_says_nothing() {
        let (tx, rx) = watch::channel(TrayState {
            items: vec![item(":1.1", "same")],
            watcher_present: true,
        });
        let (events, mut rx_events) = broadcast::channel(EVENT_CAPACITY);

        publish(&tx, &events, vec![item(":1.1", "same")], true);

        assert!(!rx.has_changed().unwrap());
        assert!(rx_events.try_recv().is_err());
    }

    #[test]
    fn a_watcher_that_went_away_empties_the_tray_and_says_so() {
        let (tx, _rx) = watch::channel(TrayState {
            items: vec![item(":1.1", "gone")],
            watcher_present: true,
        });
        let (events, mut rx_events) = broadcast::channel(EVENT_CAPACITY);

        publish(&tx, &events, Vec::new(), false);

        assert!(!tx.borrow().watcher_present);
        assert!(tx.borrow().items.is_empty());
        assert_eq!(
            rx_events.try_recv().unwrap(),
            TrayEvent::ItemUnregistered(":1.1/StatusNotifierItem".into())
        );
    }
}
