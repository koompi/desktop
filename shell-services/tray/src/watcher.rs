//! Watcher mode: owning `org.kde.StatusNotifierWatcher` and serving it.
//!
//! Opt-in, and deliberately hard to reach by accident. On a running KOOMPI seat Quickshell
//! owns this name, and a second owner takes the tray away from the desktop, so this asks
//! for the name **without** `ReplaceExisting`: where `registrar.rs:324` displaces a stale
//! global-menu daemon on purpose, a watcher that displaced the live one would cost the user
//! every icon in their panel. What it keeps from `registrar.rs` is the other half, the part
//! that matters here: `AllowReplacement`, a `NameOwnerChanged` subscription, and the rule
//! that losing the name changes what we claim rather than ending the process.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use futures_util::StreamExt;
use koompi_service::{drain, Error, Result};
use zbus::fdo::{RequestNameFlags, RequestNameReply};
use zbus::object_server::SignalEmitter;
use zbus::{Connection, MatchRule, MessageStream};

use crate::item::ItemAddress;

pub const WATCHER_NAME: &str = "org.kde.StatusNotifierWatcher";
pub const WATCHER_PATH: &str = "/StatusNotifierWatcher";

/// The version every implementation of this protocol reports.
const PROTOCOL_VERSION: i32 = 0;

#[derive(Debug, Clone, PartialEq, Eq)]
struct Registered {
    address: ItemAddress,
    /// The connection that registered it, which is what `NameOwnerChanged` names when the
    /// application exits.
    owner: String,
}

#[derive(Debug, Default)]
struct Watcher {
    items: Vec<Registered>,
    hosts: Vec<String>,
}

impl Watcher {
    /// The key, when this is a registration we did not already hold.
    fn insert(&mut self, address: ItemAddress, owner: String) -> Option<String> {
        let key = address.key();
        if self.items.iter().any(|held| held.address == address) {
            return None;
        }
        self.items.push(Registered { address, owner });
        Some(key)
    }

    /// Everything that connection was exporting, now that it is gone.
    fn drop_owner(&mut self, owner: &str) -> Vec<String> {
        let (gone, kept) = std::mem::take(&mut self.items)
            .into_iter()
            .partition::<Vec<_>, _>(|held| held.owner == owner);
        self.items = kept;
        self.hosts.retain(|host| host != owner);
        gone.iter().map(|held| held.address.key()).collect()
    }

    fn keys(&self) -> Vec<String> {
        self.items.iter().map(|held| held.address.key()).collect()
    }
}

#[zbus::interface(name = "org.kde.StatusNotifierWatcher")]
impl Watcher {
    /// The argument is a bus name or an object path; when it is a path, the item lives on
    /// the caller's own connection and only the sender says where.
    async fn register_status_notifier_item(
        &mut self,
        service: &str,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        let sender = header
            .sender()
            .ok_or_else(|| zbus::fdo::Error::Failed("registration with no sender".into()))?
            .to_string();
        let address = ItemAddress::from_registration(service, &sender)
            .ok_or_else(|| zbus::fdo::Error::InvalidArgs(format!("not an item: {service}")))?;

        let Some(key) = self.insert(address, sender) else {
            return Ok(());
        };
        Watcher::status_notifier_item_registered(&emitter, &key).await?;
        self.registered_status_notifier_items_changed(&emitter).await?;
        Ok(())
    }

    async fn register_status_notifier_host(
        &mut self,
        service: &str,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        // A host names itself, but it is the connection it named itself on that we watch
        // for going away.
        let owner = header.sender().map_or_else(String::new, |s| s.to_string());
        let host = if owner.is_empty() {
            service.to_owned()
        } else {
            owner
        };
        if !self.hosts.contains(&host) {
            self.hosts.push(host);
            Watcher::status_notifier_host_registered(&emitter).await?;
            self.is_status_notifier_host_registered_changed(&emitter)
                .await?;
        }
        Ok(())
    }

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> Vec<String> {
        self.keys()
    }

    #[zbus(property)]
    fn is_status_notifier_host_registered(&self) -> bool {
        !self.hosts.is_empty()
    }

    #[zbus(property)]
    fn protocol_version(&self) -> i32 {
        PROTOCOL_VERSION
    }

    #[zbus(signal)]
    async fn status_notifier_item_registered(
        emitter: &SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_item_unregistered(
        emitter: &SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_registered(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

/// A served `org.kde.StatusNotifierWatcher`, whether or not it currently holds the name.
///
/// The object is exported either way, because exporting it is what makes the answers
/// possible; [`WatcherService::owns_name`] is the only thing that says those answers are
/// the ones applications are getting.
pub struct WatcherService {
    conn: Connection,
    owns_name: Arc<AtomicBool>,
    task: tokio::task::JoinHandle<()>,
}

impl Drop for WatcherService {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl WatcherService {
    /// Never call this on a session bus that already has a tray. See the module note.
    pub async fn start(conn: Connection) -> Result<Self> {
        conn.object_server()
            .at(WATCHER_PATH, Watcher::default())
            .await?;

        // AllowReplacement and no ReplaceExisting: we hand the name on to whoever asks for
        // it, and we never take it from whoever has it. Queued, so a watcher started
        // before the real one still ends up serving if that one exits.
        let reply = conn
            .request_name_with_flags(WATCHER_NAME, RequestNameFlags::AllowReplacement.into())
            .await?;
        let owns_name = Arc::new(AtomicBool::new(matches!(
            reply,
            RequestNameReply::PrimaryOwner | RequestNameReply::AlreadyOwner
        )));

        let task = tokio::spawn(follow_the_bus(conn.clone(), Arc::clone(&owns_name)));

        Ok(Self {
            conn,
            owns_name,
            task,
        })
    }

    pub fn owns_name(&self) -> bool {
        self.owns_name.load(Ordering::SeqCst)
    }

    pub async fn items(&self) -> Result<Vec<String>> {
        Ok(self.interface().await?.get().await.keys())
    }

    pub async fn is_host_registered(&self) -> Result<bool> {
        Ok(!self.interface().await?.get().await.hosts.is_empty())
    }

    async fn interface(&self) -> Result<zbus::object_server::InterfaceRef<Watcher>> {
        self.conn
            .object_server()
            .interface::<_, Watcher>(WATCHER_PATH)
            .await
            .map_err(Error::Bus)
    }
}

/// Two things arrive on the same signal: the name changing hands, and an application that
/// had registered an item disappearing. A watcher that misses the second one keeps handing
/// hosts icons for processes that have exited.
async fn follow_the_bus(conn: Connection, owns_name: Arc<AtomicBool>) {
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.DBus")
        .and_then(|rule| rule.member("NameOwnerChanged"))
        .map(|rule| rule.build());
    let Ok(rule) = rule else { return };
    let Ok(changes) = MessageStream::for_match_rule(rule, &conn, Some(32)).await else {
        return;
    };
    // `forget` below awaits this same connection, and a desktop session ending hands
    // every name back at once: see `koompi_service::drain`.
    let mut changes = drain(changes, |message| {
        message.body().deserialize::<(String, String, String)>().ok()
    });

    let me = conn.unique_name().map(|name| name.to_string());

    while let Some((name, _old, new_owner)) = changes.next().await {

        if name == WATCHER_NAME {
            let ours = !new_owner.is_empty() && Some(&new_owner) == me.as_ref();
            owns_name.store(ours, Ordering::SeqCst);
            continue;
        }

        if !new_owner.is_empty() {
            continue;
        }
        forget(&conn, &name).await;
    }
}

async fn forget(conn: &Connection, owner: &str) {
    let Ok(iface) = conn
        .object_server()
        .interface::<_, Watcher>(WATCHER_PATH)
        .await
    else {
        return;
    };

    let gone = iface.get_mut().await.drop_owner(owner);
    if gone.is_empty() {
        return;
    }
    for key in gone {
        let _ = Watcher::status_notifier_item_unregistered(iface.signal_emitter(), &key).await;
    }
    let _ = iface
        .get()
        .await
        .registered_status_notifier_items_changed(iface.signal_emitter())
        .await;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn address(key: &str) -> ItemAddress {
        ItemAddress::parse(key).unwrap()
    }

    #[test]
    fn the_same_item_registering_twice_is_registered_once() {
        let mut watcher = Watcher::default();

        assert_eq!(
            watcher.insert(address(":1.5/StatusNotifierItem"), ":1.5".into()),
            Some(":1.5/StatusNotifierItem".to_owned())
        );
        assert_eq!(
            watcher.insert(address(":1.5/StatusNotifierItem"), ":1.5".into()),
            None
        );
        assert_eq!(watcher.keys().len(), 1);
    }

    #[test]
    fn a_connection_going_away_takes_every_item_it_exported() {
        let mut watcher = Watcher::default();
        watcher.insert(address(":1.5/StatusNotifierItem"), ":1.5".into());
        watcher.insert(address(":1.5/org/ayatana/NotificationItem/x"), ":1.5".into());
        watcher.insert(address(":1.9/StatusNotifierItem"), ":1.9".into());
        watcher.hosts.push(":1.5".into());

        let gone = watcher.drop_owner(":1.5");

        assert_eq!(gone.len(), 2);
        assert_eq!(watcher.keys(), [":1.9/StatusNotifierItem"]);
        assert!(!watcher.is_status_notifier_host_registered());
        assert!(watcher.drop_owner(":1.5").is_empty());
    }

    #[test]
    fn an_item_registered_by_a_well_known_name_is_still_dropped_with_its_connection() {
        let mut watcher = Watcher::default();
        watcher.insert(address("org.kde.StatusNotifierItem-9-1"), ":1.9".into());

        assert_eq!(
            watcher.drop_owner(":1.9"),
            ["org.kde.StatusNotifierItem-9-1/StatusNotifierItem"]
        );
    }

    mod bus {
        //! Everything here needs a bus of its own, and refuses to run on one that is not.
        //! `dbus-run-session -- cargo test -p koompi-tray -- --ignored --test-threads=1`.

        use super::*;
        use crate::menu::{MenuItem, ToggleState, ToggleType};
        use crate::proxy::StatusNotifierWatcherProxy;
        use crate::{TrayConfig, TrayEvent, TrayService};
        use koompi_service::Service;
        use std::collections::HashMap;
        use std::time::Duration;
        use tokio::sync::Mutex;
        use tokio::sync::mpsc::{self, UnboundedSender};
        use zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Structure, Value};

        /// One bus, one watcher name. The tests take it in turn.
        static NAME: Mutex<()> = Mutex::const_new(());

        const ITEM_PATH: &str = "/StatusNotifierItem";
        const MENU_PATH: &str = "/MenuBar";
        const ICON: [u8; 16] = [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        ];

        /// The guard on every stop condition in this job. A session bus with a desktop on
        /// it has dozens of well-known names; a bus from `dbus-run-session` has exactly
        /// one, and only on that one is claiming the watcher name harmless.
        async fn private_bus() -> Connection {
            let conn = Connection::session()
                .await
                .expect("no session bus; run under dbus-run-session");
            let names = zbus::fdo::DBusProxy::new(&conn)
                .await
                .unwrap()
                .list_names()
                .await
                .unwrap();
            let well_known: Vec<String> = names
                .iter()
                .map(|name| name.to_string())
                .filter(|name| !name.starts_with(':'))
                .collect();

            assert_eq!(
                well_known,
                ["org.freedesktop.DBus"],
                "refusing to touch a bus that is not private: run under dbus-run-session"
            );
            conn
        }

        struct FakeItem {
            calls: UnboundedSender<String>,
        }

        #[zbus::interface(name = "org.kde.StatusNotifierItem")]
        impl FakeItem {
            async fn activate(&self, x: i32, y: i32) {
                let _ = self.calls.send(format!("Activate({x},{y})"));
            }

            async fn secondary_activate(&self, x: i32, y: i32) {
                let _ = self.calls.send(format!("SecondaryActivate({x},{y})"));
            }

            async fn context_menu(&self, x: i32, y: i32) {
                let _ = self.calls.send(format!("ContextMenu({x},{y})"));
            }

            async fn scroll(&self, delta: i32, orientation: String) {
                let _ = self.calls.send(format!("Scroll({delta},{orientation})"));
            }

            #[zbus(property)]
            fn id(&self) -> &str {
                "FakeItem"
            }

            #[zbus(property)]
            fn title(&self) -> &str {
                "A Fake Item"
            }

            #[zbus(property)]
            fn category(&self) -> &str {
                "SystemServices"
            }

            #[zbus(property)]
            fn status(&self) -> &str {
                "Active"
            }

            #[zbus(property)]
            fn icon_name(&self) -> &str {
                "fake-symbolic"
            }

            #[zbus(property)]
            fn icon_pixmap(&self) -> Vec<(i32, i32, Vec<u8>)> {
                vec![(2, 2, ICON.to_vec())]
            }

            #[zbus(property)]
            fn item_is_menu(&self) -> bool {
                true
            }

            #[zbus(property)]
            fn menu(&self) -> OwnedObjectPath {
                ObjectPath::from_static_str(MENU_PATH).unwrap().into()
            }
        }

        struct FakeMenu {
            calls: UnboundedSender<String>,
        }

        type Node = (i32, HashMap<String, OwnedValue>, Vec<OwnedValue>);

        fn leaf(id: i32, pairs: &[(&str, Value<'static>)]) -> OwnedValue {
            let props: HashMap<String, OwnedValue> = pairs
                .iter()
                .map(|(k, v)| {
                    (
                        (*k).to_owned(),
                        OwnedValue::try_from(v.try_clone().unwrap()).unwrap(),
                    )
                })
                .collect();
            let node = Structure::from((id, props, Vec::<OwnedValue>::new()));
            OwnedValue::try_from(Value::from(node)).unwrap()
        }

        #[zbus::interface(name = "com.canonical.dbusmenu")]
        impl FakeMenu {
            async fn get_layout(
                &self,
                parent: i32,
                _depth: i32,
                _properties: Vec<String>,
            ) -> (u32, Node) {
                let _ = self.calls.send(format!("GetLayout({parent})"));
                let children = vec![
                    leaf(1, &[("label", "Open".into())]),
                    leaf(
                        2,
                        &[
                            ("label", "Notifications".into()),
                            ("toggle-type", "checkmark".into()),
                            ("toggle-state", 1i32.into()),
                        ],
                    ),
                    leaf(3, &[("type", "separator".into())]),
                ];
                (1, (0, HashMap::new(), children))
            }

            async fn about_to_show(&self, id: i32) -> bool {
                let _ = self.calls.send(format!("AboutToShow({id})"));
                false
            }

            async fn event(&self, id: i32, kind: String, _data: Value<'_>, _timestamp: u32) {
                let _ = self.calls.send(format!("Event({id},{kind})"));
            }
        }

        async fn serve_fake_item(calls: UnboundedSender<String>) -> Connection {
            let conn = Connection::session().await.unwrap();
            conn.object_server()
                .at(ITEM_PATH, FakeItem { calls: calls.clone() })
                .await
                .unwrap();
            conn.object_server()
                .at(MENU_PATH, FakeMenu { calls })
                .await
                .unwrap();

            StatusNotifierWatcherProxy::new(&conn)
                .await
                .unwrap()
                .register_status_notifier_item(ITEM_PATH)
                .await
                .unwrap();
            conn
        }

        async fn settle() {
            tokio::time::sleep(Duration::from_millis(150)).await;
        }

        #[tokio::test]
        #[ignore = "claims org.kde.StatusNotifierWatcher; private bus only"]
        async fn the_watcher_takes_a_registration_and_announces_it() {
            let _held = NAME.lock().await;
            let conn = private_bus().await;
            let watcher = WatcherService::start(conn.clone()).await.unwrap();
            assert!(watcher.owns_name(), "did not get the name on an empty bus");

            let listener = Connection::session().await.unwrap();
            let proxy = StatusNotifierWatcherProxy::new(&listener).await.unwrap();
            assert_eq!(proxy.protocol_version().await.unwrap(), PROTOCOL_VERSION);
            assert!(!proxy.is_status_notifier_host_registered().await.unwrap());

            let mut registrations = zbus::MessageStream::for_match_rule(
                MatchRule::builder()
                    .msg_type(zbus::message::Type::Signal)
                    .interface(WATCHER_NAME)
                    .unwrap()
                    .member("StatusNotifierItemRegistered")
                    .unwrap()
                    .build(),
                &listener,
                Some(8),
            )
            .await
            .unwrap();

            let (calls, _rx) = mpsc::unbounded_channel();
            let item = serve_fake_item(calls).await;
            let announced = tokio::time::timeout(Duration::from_secs(5), registrations.next())
                .await
                .expect("no StatusNotifierItemRegistered within 5s")
                .unwrap()
                .unwrap();
            let announced: String = announced.body().deserialize().unwrap();

            let expected = format!("{}{ITEM_PATH}", item.unique_name().unwrap());
            assert_eq!(announced, expected);
            assert_eq!(
                watcher.items().await.unwrap(),
                std::slice::from_ref(&expected)
            );
            assert_eq!(
                proxy.registered_status_notifier_items().await.unwrap(),
                [expected]
            );

            drop(item);
            settle().await;
            assert!(
                watcher.items().await.unwrap().is_empty(),
                "an item whose application exited stayed registered"
            );

            conn.release_name(WATCHER_NAME).await.unwrap();
        }

        #[tokio::test]
        #[ignore = "claims org.kde.StatusNotifierWatcher; private bus only"]
        async fn losing_the_name_is_survived_and_the_queue_hands_it_back() {
            let _held = NAME.lock().await;
            let first_bus = private_bus().await;
            let first = WatcherService::start(first_bus.clone()).await.unwrap();
            assert!(first.owns_name());

            let second_bus = Connection::session().await.unwrap();
            let second = WatcherService::start(second_bus.clone()).await.unwrap();
            settle().await;
            assert!(
                !second.owns_name(),
                "a second watcher took the name from the first"
            );
            assert!(first.owns_name(), "the first watcher lost the name to a queue");

            first_bus.release_name(WATCHER_NAME).await.unwrap();
            settle().await;

            assert!(!first.owns_name(), "the first watcher still claims the name");
            assert!(second.owns_name(), "the queued watcher never got the name");

            second_bus.release_name(WATCHER_NAME).await.unwrap();
        }

        #[tokio::test]
        #[ignore = "claims org.kde.StatusNotifierWatcher; private bus only"]
        async fn a_host_reads_an_item_end_to_end_and_its_actions_arrive() {
            let _held = NAME.lock().await;
            let bus = private_bus().await;
            let watcher = WatcherService::start(bus.clone()).await.unwrap();
            assert!(watcher.owns_name());

            let (calls, mut heard) = mpsc::unbounded_channel();
            let item_conn = serve_fake_item(calls).await;
            let item_name = item_conn.unique_name().unwrap().to_string();

            let host = TrayService::with_connection(
                Connection::session().await.unwrap(),
                TrayConfig::default(),
            )
            .await
            .unwrap();
            let mut events = host.events();

            assert!(watcher.is_host_registered().await.unwrap());
            let state = host.state();
            assert!(state.watcher_present);
            assert_eq!(state.items.len(), 1, "host did not see the registered item");

            let item = &state.items[0];
            let key = item.key();
            assert_eq!(key, format!("{item_name}{ITEM_PATH}"));
            assert_eq!(item.id, "FakeItem");
            assert_eq!(item.title, "A Fake Item");
            assert_eq!(item.category.as_str(), "SystemServices");
            assert_eq!(item.status.as_str(), "Active");
            assert_eq!(item.icon_name, "fake-symbolic");
            assert_eq!(item.icon_pixmap.len(), 1);
            assert_eq!(item.icon_pixmap[0].argb32, ICON, "icon bytes were not raw");
            assert!(item.item_is_menu);
            assert_eq!(item.menu.as_deref(), Some(MENU_PATH));

            // The three calls the stop conditions forbid against a real item, against ours.
            host.activate(&key, 4, 2).await.unwrap();
            host.secondary_activate(&key, 5, 6).await.unwrap();
            host.context_menu(&key, 7, 8).await.unwrap();
            host.scroll(&key, -120, "vertical").await.unwrap();
            host.click(&key, 2).await.unwrap();

            let menu = host.menu(&key).await.unwrap();
            assert_eq!(menu.children.len(), 3);
            assert_eq!(menu.children[0].label, "Open");
            assert_eq!(menu.children[1].toggle_type, ToggleType::Checkmark);
            assert_eq!(menu.children[1].toggle_state, ToggleState::On);
            assert!(menu.children[2].separator && !menu.children[2].enabled);
            assert_eq!(menu.walk().len(), 4);
            assert_eq!(MenuItem::default().id, 0);

            let mut seen = Vec::new();
            while let Ok(call) = heard.try_recv() {
                seen.push(call);
            }
            assert_eq!(
                seen,
                [
                    "Activate(4,2)",
                    "SecondaryActivate(5,6)",
                    "ContextMenu(7,8)",
                    "Scroll(-120,vertical)",
                    "Event(2,clicked)",
                    "AboutToShow(0)",
                    "GetLayout(0)",
                ]
            );

            // The application exits: the watcher drops it and the host follows.
            drop(item_conn);
            settle().await;
            assert!(
                host.state().items.is_empty(),
                "the host kept an item whose application had exited"
            );
            let mut unregistered = Vec::new();
            while let Ok(event) = events.try_recv() {
                unregistered.push(event);
            }
            assert!(unregistered.contains(&TrayEvent::ItemUnregistered(key)));

            bus.release_name(WATCHER_NAME).await.unwrap();
        }
    }
}
