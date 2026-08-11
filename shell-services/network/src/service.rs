//! One signal subscription on the system bus, selective reads, and a `watch` of the
//! result. Nothing here spawns a process.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_util::StreamExt;
use koompi_service::{Backoff, Error, PollRate, Result, Service};
use tokio::sync::{broadcast, mpsc, watch};
use tokio::task::JoinHandle;
use tokio::time::Instant;
use zbus::fdo::PropertiesProxy;
use zbus::names::InterfaceName;
use zbus::proxy::CacheProperties;
use zbus::{Connection, MatchRule, MessageStream};
use zvariant::{ObjectPath, OwnedValue, Value};

use crate::ap::{AccessPoint, Ssid};
use crate::enums::{ActiveState, Connectivity, DeviceState, DeviceType, NmState, WifiStatus};
use crate::model::{ActiveConnection, Device, NetworkState, WiredDevice};
use crate::props::{self, Props};
use crate::proxy::{
    ConnectionSettings, DeviceWirelessProxy, NetworkManagerProxy, SettingsConnectionProxy,
    ACTIVE_IFACE, AP_IFACE, DEVICE_IFACE, MANAGER_IFACE, NM, NM_PATH, WIRED_IFACE, WIRELESS_IFACE,
};
use crate::refresh::{refresh_for_properties, refresh_for_signal, Refresh};
use crate::settings::{profile_with_psk, wifi_profile};

/// NetworkManager emits several signals per state change, and a scan landing adds every
/// access point in range one at a time. The QML has no equivalent: `Network.qml:174`
/// re-runs five queries per `nmcli monitor` line, undebounced.
const DEBOUNCE_BASE: Duration = Duration::from_millis(100);

/// A `RequestScan` that has produced no new `LastScan` by then is not still running.
const SCAN_TIMEOUT: Duration = Duration::from_secs(30);

const REFRESH_CAPACITY: usize = 64;

#[derive(Debug, Clone, Copy)]
struct ScanRequest {
    /// `LastScan` as it stood when the scan was asked for.
    baseline: i64,
    at: Instant,
}

pub struct NetworkService {
    ctx: Arc<Ctx>,
    tx: watch::Sender<NetworkState>,
    refreshes: broadcast::Sender<Refresh>,
    poll_rate: Arc<AtomicU32>,
    worker: JoinHandle<()>,
}

impl Service for NetworkService {
    type State = NetworkState;

    fn state(&self) -> NetworkState {
        self.tx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<NetworkState> {
        self.tx.subscribe()
    }
}

impl Drop for NetworkService {
    fn drop(&mut self) {
        self.worker.abort();
    }
}

impl NetworkService {
    pub async fn connect(rate: PollRate) -> Result<Self> {
        Self::with_connection(Connection::system().await?, rate).await
    }

    pub async fn with_connection(conn: Connection, rate: PollRate) -> Result<Self> {
        let manager = NetworkManagerProxy::new(&conn).await?;
        let ctx = Arc::new(Ctx {
            conn,
            manager,
            scan: Mutex::new(None),
        });

        let mut state = NetworkState {
            poll_rate: rate,
            ..NetworkState::default()
        };
        apply(&ctx, &mut state, Refresh::ALL, &[])
            .await
            .map_err(unavailable)?;

        let tx = watch::Sender::new(state);
        let refreshes = broadcast::Sender::new(REFRESH_CAPACITY);
        let poll_rate = Arc::new(AtomicU32::new(rate.factor()));
        let worker = Worker {
            ctx: Arc::clone(&ctx),
            tx: tx.clone(),
            refreshes: refreshes.clone(),
            poll_rate: Arc::clone(&poll_rate),
        };

        Ok(Self {
            ctx,
            tx,
            refreshes,
            poll_rate,
            worker: tokio::spawn(worker.run()),
        })
    }

    /// What each coalesced burst of signals actually invalidated. `watch` says the state
    /// moved; this says how little had to be read to find out, which is the whole of the
    /// difference from `Network.qml:174`.
    pub fn refreshes(&self) -> broadcast::Receiver<Refresh> {
        self.refreshes.subscribe()
    }

    pub fn poll_rate(&self) -> PollRate {
        PollRate::new(self.poll_rate.load(Ordering::Relaxed))
    }

    /// `PowerSaving.qml:33`, applied to the coalescing window rather than to a timer:
    /// this crate never polls.
    pub fn set_poll_rate(&self, rate: PollRate) {
        self.poll_rate.store(rate.factor(), Ordering::Relaxed);
        self.tx.send_if_modified(|state| {
            let changed = state.poll_rate != rate;
            state.poll_rate = rate;
            changed
        });
    }

    pub fn debounce(&self) -> Duration {
        self.poll_rate().interval(DEBOUNCE_BASE)
    }

    /// `Network.qml:147`, `nmcli dev wifi list --rescan yes`. The one write here that is
    /// exercised against the live seat: the shell already fires it from a button.
    pub async fn request_scan(&self) -> Result<()> {
        let device = self.wireless().await?;
        let baseline = self.tx.borrow().wifi.last_scan;
        device.request_scan(&HashMap::new()).await?;

        if let Ok(mut scan) = self.ctx.scan.lock() {
            *scan = Some(ScanRequest {
                baseline,
                at: Instant::now(),
            });
        }
        self.tx.send_if_modified(|state| {
            let was = state.wifi.scanning;
            state.wifi.scanning = true;
            !was
        });
        Ok(())
    }

    /// `Network.qml:60`, `nmcli radio wifi on|off`. Never called against this seat.
    pub async fn set_wireless_enabled(&self, enabled: bool) -> Result<()> {
        self.ctx.manager.set_wireless_enabled(enabled).await?;
        Ok(())
    }

    /// `Network.qml:76`, `nmcli dev wifi connect <ssid>`, which the QML's own comment
    /// notes is chosen because it creates the profile as well. Never called against
    /// this seat.
    pub async fn connect_to(
        &self,
        access_point: &AccessPoint,
        passphrase: Option<&str>,
    ) -> Result<String> {
        let (device_path, _) = self.wireless_paths()?;
        let profile = wifi_profile(&access_point.ssid, access_point.security, passphrase)?;

        let device = object_path(&device_path)?;
        let specific = object_path(&access_point.path)?;
        let (_, active) = self
            .ctx
            .manager
            .add_and_activate_connection(&profile, &device, &specific)
            .await?;
        Ok(active.as_str().to_owned())
    }

    /// `Network.qml:81`, `nmcli connection down <ssid>`. Never called against this seat.
    pub async fn disconnect(&self) -> Result<()> {
        let active = self
            .wifi_active_connection()
            .ok_or_else(|| Error::Unavailable("an active wireless connection".into()))?;
        let path = object_path(&active)?;
        self.ctx.manager.deactivate_connection(&path).await?;
        Ok(())
    }

    /// `Network.qml:96`, `nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"`.
    ///
    /// Never called, on this seat or any other, by anything in this campaign: a wrong
    /// passphrase written to a saved profile locks the user out of their own network.
    /// [`crate::settings::profile_with_psk`] is what carries the tests.
    pub async fn set_passphrase(&self, settings_path: &str, passphrase: &str) -> Result<()> {
        let connection = SettingsConnectionProxy::builder(&self.ctx.conn)
            .destination(NM)?
            .path(settings_path.to_owned())?
            .cache_properties(CacheProperties::No)
            .build()
            .await?;

        let saved = connection.get_settings().await?;
        let updated = profile_with_psk(&saved, passphrase)?;
        connection.update(&updated).await?;
        Ok(())
    }

    /// The saved profile a passphrase change would target, so a caller never has to
    /// guess an object path.
    pub fn saved_profile_of(&self, ssid: &Ssid) -> Option<String> {
        let name = ssid.to_lossy().into_owned();
        self.tx
            .borrow()
            .active_connections
            .iter()
            .find(|c| c.id == name && !c.settings_path.is_empty())
            .map(|c| c.settings_path.clone())
    }

    fn wireless_paths(&self) -> Result<(String, String)> {
        let state = self.tx.borrow();
        if !state.wifi.present {
            return Err(Error::Unavailable("a wireless device".into()));
        }
        Ok((
            state.wifi.device_path.clone(),
            state.wifi.active_ap_path.clone(),
        ))
    }

    fn wifi_active_connection(&self) -> Option<String> {
        let state = self.tx.borrow();
        let device = state.wifi.device_path.clone();
        state
            .active_connections
            .iter()
            .find(|c| c.devices.contains(&device))
            .map(|c| c.path.clone())
    }

    async fn wireless(&self) -> Result<DeviceWirelessProxy<'static>> {
        let (device_path, _) = self.wireless_paths()?;
        Ok(DeviceWirelessProxy::builder(&self.ctx.conn)
            .destination(NM)?
            .path(device_path)?
            .cache_properties(CacheProperties::No)
            .build()
            .await?)
    }
}

struct Ctx {
    conn: Connection,
    manager: NetworkManagerProxy<'static>,
    scan: Mutex<Option<ScanRequest>>,
}

struct Worker {
    ctx: Arc<Ctx>,
    tx: watch::Sender<NetworkState>,
    refreshes: broadcast::Sender<Refresh>,
    poll_rate: Arc<AtomicU32>,
}

impl Worker {
    async fn run(self) {
        let mut backoff = Backoff::default();
        loop {
            if self.session().await.is_ok() {
                backoff.reset();
            }
            self.tx.send_if_modified(|state| {
                let was = state.available;
                state.available = false;
                was
            });
            backoff.wait().await;
        }
    }

    /// One subscription for the whole daemon, not one per object. An access point that
    /// appears after start, or a USB dongle plugged in later, needs no new match rule.
    async fn session(&self) -> Result<()> {
        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .sender(NM)?
            .build();
        let signals = MessageStream::for_match_rule(rule, &self.ctx.conn, Some(64)).await?;
        let (mut signals, _drain) = drain(signals);

        let mut state = self.tx.borrow().clone();
        apply(&self.ctx, &mut state, Refresh::ALL, &[]).await?;
        self.publish(state.clone());

        let mut pending = Refresh::NONE;
        let mut touched: Vec<String> = Vec::new();
        let mut deadline: Option<Instant> = None;

        loop {
            tokio::select! {
                signal = signals.recv() => {
                    let Some((refresh, path)) = signal else { return Ok(()) };
                    pending.merge(refresh);
                    if refresh.access_point {
                        if let Some(path) = path {
                            if !touched.contains(&path) {
                                touched.push(path);
                            }
                        }
                    }
                    deadline = Some(Instant::now() + self.debounce());
                }
                () = sleep_until(deadline) => {
                    deadline = None;
                    let refresh = std::mem::replace(&mut pending, Refresh::NONE);
                    let paths = std::mem::take(&mut touched);

                    state.poll_rate = self.rate();
                    apply(&self.ctx, &mut state, refresh, &paths).await?;
                    self.publish(state.clone());
                    let _ = self.refreshes.send(refresh);
                }
            }
        }
    }

    fn rate(&self) -> PollRate {
        PollRate::new(self.poll_rate.load(Ordering::Relaxed))
    }

    fn debounce(&self) -> Duration {
        self.rate().interval(DEBOUNCE_BASE)
    }

    /// A signal strength that ticked and came back to the same number is not a change a
    /// consumer should be woken for.
    fn publish(&self, next: NetworkState) {
        self.tx.send_if_modified(|current| {
            if *current == next {
                return false;
            }
            *current = next;
            true
        });
    }
}

/// Aborts the drain when the session that started it ends, the way `NetworkService`
/// drops its worker.
struct Drain(JoinHandle<()>);

impl Drop for Drain {
    fn drop(&mut self) {
        self.0.abort();
    }
}

/// zbus hands a signal to a stream with `broadcast_direct`, which waits for room rather
/// than dropping, and one task per connection reads the socket for both signals and
/// method replies. A loop that polls the stream only between `apply` calls therefore
/// deadlocks its own connection the first time a burst fills the stream while `apply` is
/// awaiting a reply: the reply is behind the blocked reader, `apply` never returns, and
/// nothing drains the stream. Associating with a new access point is such a burst.
///
/// Nothing here awaits the connection, so the reader is never the thing left waiting.
fn drain(mut signals: MessageStream) -> (mpsc::UnboundedReceiver<(Refresh, Option<String>)>, Drain) {
    let (tx, rx) = mpsc::unbounded_channel();
    let task = tokio::spawn(async move {
        while let Some(message) = signals.next().await {
            let Ok(message) = message else { continue };
            let classified = classify(&message);
            if classified.0.is_empty() {
                continue;
            }
            if tx.send(classified).is_err() {
                return;
            }
        }
    });
    (rx, Drain(task))
}

/// What the message invalidated, and the object it came from when that object is a
/// single access point.
fn classify(message: &zbus::Message) -> (Refresh, Option<String>) {
    let header = message.header();
    let path = header.path().map(|p| p.as_str().to_owned());
    let member = header.member().map(|m| m.as_str().to_owned());

    if member.as_deref() == Some("PropertiesChanged") {
        let body = message.body();
        let Ok((interface, changed, invalidated)) =
            body.deserialize::<(String, HashMap<String, Value<'_>>, Vec<String>)>()
        else {
            return (Refresh::NONE, None);
        };
        let keys: Vec<&str> = changed
            .keys()
            .map(String::as_str)
            .chain(invalidated.iter().map(String::as_str))
            .collect();
        return (refresh_for_properties(&interface, &keys), path);
    }

    let interface = header.interface().map(|i| i.as_str()).unwrap_or_default();
    (
        refresh_for_signal(interface, member.as_deref().unwrap_or_default()),
        path,
    )
}

async fn properties(conn: &Connection, path: &str) -> zbus::Result<PropertiesProxy<'static>> {
    PropertiesProxy::builder(conn)
        .destination(NM)?
        .path(path.to_owned())?
        .cache_properties(CacheProperties::No)
        .build()
        .await
}

async fn get_all(conn: &Connection, path: &str, interface: &str) -> zbus::Result<Props> {
    let interface = InterfaceName::try_from(interface)?;
    properties(conn, path)
        .await?
        .get_all(interface)
        .await
        .map_err(Into::into)
}

/// An object that went away between the signal and the read is normal traffic on this
/// bus, not a fault: an access point drops out of range mid-refresh all the time.
async fn try_get_all(conn: &Connection, path: &str, interface: &str) -> Option<Props> {
    get_all(conn, path, interface).await.ok()
}

fn object_path(path: &str) -> Result<ObjectPath<'static>> {
    ObjectPath::try_from(path.to_owned())
        .map_err(|error| Error::Protocol(format!("{path}: {error}")))
}

/// The bus name simply not being there is a seat without NetworkManager, which is a
/// working seat. Anything else is a real failure.
fn unavailable(error: Error) -> Error {
    let absent = match &error {
        Error::Bus(zbus::Error::FDO(fdo)) => matches!(
            **fdo,
            zbus::fdo::Error::ServiceUnknown(_) | zbus::fdo::Error::NameHasNoOwner(_)
        ),
        Error::Bus(zbus::Error::MethodError(name, _, _)) => matches!(
            name.as_str(),
            "org.freedesktop.DBus.Error.ServiceUnknown"
                | "org.freedesktop.DBus.Error.NameHasNoOwner"
        ),
        _ => false,
    };
    match absent {
        true => Error::Unavailable("NetworkManager".into()),
        false => error,
    }
}

async fn apply(
    ctx: &Ctx,
    state: &mut NetworkState,
    refresh: Refresh,
    access_points: &[String],
) -> Result<()> {
    if refresh.is_empty() {
        return Ok(());
    }

    if refresh.manager || refresh.devices || refresh.active {
        let manager = get_all(&ctx.conn, NM_PATH, MANAGER_IFACE).await?;
        state.available = true;

        if refresh.manager {
            state.version = props::text(&manager, "Version").unwrap_or_default();
            state.state = NmState::from_u32(props::u32_at(&manager, "State").unwrap_or(0));
            state.connectivity =
                Connectivity::from_u32(props::u32_at(&manager, "Connectivity").unwrap_or(0));
            state.wifi.enabled = props::boolean(&manager, "WirelessEnabled").unwrap_or(false);
        }
        if refresh.active {
            read_active_connections(ctx, state, &manager).await;
        }
        if refresh.devices {
            read_devices(ctx, state, &manager).await;
        }
    }

    if refresh.wifi && !refresh.devices {
        read_wireless(ctx, state).await;
    }
    if refresh.wired && !refresh.devices {
        read_wired(ctx, state).await;
    }
    if refresh.access_points && !refresh.devices {
        read_access_points(ctx, state).await;
    }
    if refresh.access_point && !refresh.devices && !refresh.access_points {
        for path in access_points {
            let Some(props) = try_get_all(&ctx.conn, path, AP_IFACE).await else {
                state.wifi.networks.retain(|ap| ap.path != *path);
                continue;
            };
            let fresh = AccessPoint::from_props(path, &props);
            match state.wifi.networks.iter_mut().find(|ap| ap.path == *path) {
                Some(existing) => *existing = fresh,
                None => state.wifi.networks.push(fresh),
            }
        }
    }

    recompute(state);
    Ok(())
}

async fn read_active_connections(ctx: &Ctx, state: &mut NetworkState, manager: &Props) {
    let paths = props::paths(manager, "ActiveConnections").unwrap_or_default();
    let mut connections = Vec::with_capacity(paths.len());
    for path in &paths {
        if let Some(props) = try_get_all(&ctx.conn, path, ACTIVE_IFACE).await {
            connections.push(ActiveConnection::from_props(path, &props));
        }
    }

    let primary = props::path(manager, "PrimaryConnection").unwrap_or_default();
    state.primary = connections.iter().find(|c| c.path == primary).cloned();
    state.active_connections = connections;
}

async fn read_devices(ctx: &Ctx, state: &mut NetworkState, manager: &Props) {
    let paths = props::paths(manager, "Devices").unwrap_or_default();

    state.wifi.present = false;
    state.wifi.device_path.clear();
    state.wired.clear();

    for path in &paths {
        let Some(props) = try_get_all(&ctx.conn, path, DEVICE_IFACE).await else {
            continue;
        };
        let device = Device::from_props(path, &props);
        match device.kind {
            // A seat with two radios draws the first; the QML cannot see a second
            // one either.
            DeviceType::Wifi if !state.wifi.present => {
                state.wifi.present = true;
                state.wifi.device_path = device.path.clone();
                state.wifi.interface = device.interface.clone();
                state.wifi.device_state = device.state;
            }
            DeviceType::Ethernet => {
                state.wired.push(WiredDevice {
                    device,
                    carrier: false,
                    speed: 0,
                    hw_address: String::new(),
                });
            }
            _ => {}
        }
    }

    read_wireless(ctx, state).await;
    read_wired(ctx, state).await;
    read_access_points(ctx, state).await;
}

async fn read_wireless(ctx: &Ctx, state: &mut NetworkState) {
    if !state.wifi.present {
        state.wifi.networks.clear();
        state.wifi.active = None;
        state.wifi.active_ap_path.clear();
        return;
    }
    let path = state.wifi.device_path.clone();

    if let Some(device) = try_get_all(&ctx.conn, &path, DEVICE_IFACE).await {
        state.wifi.device_state =
            DeviceState::from_u32(props::u32_at(&device, "State").unwrap_or(0));
        state.wifi.interface = props::text(&device, "Interface").unwrap_or_default();
    }

    let Some(wireless) = try_get_all(&ctx.conn, &path, WIRELESS_IFACE).await else {
        return;
    };
    state.wifi.hw_address = props::text(&wireless, "HwAddress").unwrap_or_default();
    state.wifi.bitrate = props::u32_at(&wireless, "Bitrate").unwrap_or(0);
    state.wifi.active_ap_path = props::path(&wireless, "ActiveAccessPoint")
        .filter(|p| p != "/")
        .unwrap_or_default();

    let last_scan = props::i64_at(&wireless, "LastScan").unwrap_or(-1);
    state.wifi.last_scan = last_scan;
    state.wifi.scanning = still_scanning(ctx, last_scan);
}

/// `Network.qml:21` sets `wifiScanning` true on the button and false when its process
/// exits. NetworkManager publishes no such flag, so the equivalent is: a scan was asked
/// for, and `LastScan` has not moved since.
fn still_scanning(ctx: &Ctx, last_scan: i64) -> bool {
    let Ok(mut scan) = ctx.scan.lock() else {
        return false;
    };
    let Some(request) = *scan else {
        return false;
    };
    if last_scan != request.baseline || request.at.elapsed() >= SCAN_TIMEOUT {
        *scan = None;
        return false;
    }
    true
}

async fn read_wired(ctx: &Ctx, state: &mut NetworkState) {
    for wired in &mut state.wired {
        if let Some(device) = try_get_all(&ctx.conn, &wired.device.path, DEVICE_IFACE).await {
            wired.device = Device::from_props(&wired.device.path, &device);
        }
        let Some(props) = try_get_all(&ctx.conn, &wired.device.path, WIRED_IFACE).await else {
            continue;
        };
        wired.carrier = props::boolean(&props, "Carrier").unwrap_or(false);
        wired.speed = props::u32_at(&props, "Speed").unwrap_or(0);
        wired.hw_address = props::text(&props, "HwAddress").unwrap_or_default();
    }
}

async fn read_access_points(ctx: &Ctx, state: &mut NetworkState) {
    if !state.wifi.present {
        state.wifi.networks.clear();
        return;
    }
    let Some(wireless) = try_get_all(&ctx.conn, &state.wifi.device_path, WIRELESS_IFACE).await
    else {
        return;
    };
    let paths = props::paths(&wireless, "AccessPoints").unwrap_or_default();

    let mut networks = Vec::with_capacity(paths.len());
    for path in &paths {
        if let Some(props) = try_get_all(&ctx.conn, path, AP_IFACE).await {
            networks.push(AccessPoint::from_props(path, &props));
        }
    }
    state.wifi.networks = networks;
}

/// Everything the QML derives in JavaScript, from what was just read.
fn recompute(state: &mut NetworkState) {
    let active_path = state.wifi.active_ap_path.clone();
    for ap in &mut state.wifi.networks {
        ap.active = !active_path.is_empty() && ap.path == active_path;
    }
    // Strongest first, which is the order `nmcli d w` prints and, unlike
    // `Network.qml:26`, does not float the associated radio to the top. The tie-breaks
    // are there so a strength that ticked back to its old value is not a spurious diff.
    state.wifi.networks.sort_by(|a, b| {
        b.strength
            .cmp(&a.strength)
            .then(a.ssid.as_bytes().cmp(b.ssid.as_bytes()))
            .then(a.hw_address.cmp(&b.hw_address))
    });
    state.wifi.active = state.wifi.networks.iter().find(|ap| ap.active).cloned();

    state.wifi.status = WifiStatus::derive(
        state.wifi.present && state.wifi.enabled,
        state.wifi.device_state,
        state.connectivity,
    );
    state.wifi.connecting = state.wifi.device_state.connecting();
    state.wifi.connect_target = connect_target(state);
}

/// `Network.qml:23` holds the access point the user picked. Here it is the wireless
/// connection NetworkManager is bringing up, whoever asked for it, so a connection
/// started from `nmtui` shows in the bar too. The profile's `Id` is text where an SSID
/// is bytes, which is the one thing lost against the QML.
fn connect_target(state: &NetworkState) -> Option<Ssid> {
    if !state.wifi.connecting {
        return None;
    }
    let device = &state.wifi.device_path;
    state
        .active_connections
        .iter()
        .find(|c| {
            c.state == ActiveState::Activating && c.devices.iter().any(|d| d == device)
        })
        .map(|c| Ssid::new(c.id.as_bytes().to_vec()))
}

async fn sleep_until(deadline: Option<Instant>) {
    match deadline {
        Some(deadline) => tokio::time::sleep_until(deadline).await,
        None => std::future::pending().await,
    }
}

/// The `AddAndActivateConnection` message a connect would put on the bus, built without
/// a connection so it can be asserted rather than fired. See the stop conditions in
/// `.work/jobs/J06-network.md`.
pub fn connect_message(
    device_path: &str,
    access_point: &AccessPoint,
    passphrase: Option<&str>,
) -> Result<zbus::message::Message> {
    let profile = wifi_profile(&access_point.ssid, access_point.security, passphrase)?;
    let device = object_path(device_path)?;
    let specific = object_path(&access_point.path)?;

    zbus::message::Message::method_call(NM_PATH, "AddAndActivateConnection")
        .and_then(|builder| builder.destination(NM))
        .and_then(|builder| builder.interface(MANAGER_IFACE))
        .and_then(|builder| builder.build(&(&profile, &device, &specific)))
        .map_err(Error::Bus)
}

/// The same, for `DeactivateConnection`.
pub fn disconnect_message(active_connection: &str) -> Result<zbus::message::Message> {
    let active = object_path(active_connection)?;
    zbus::message::Message::method_call(NM_PATH, "DeactivateConnection")
        .and_then(|builder| builder.destination(NM))
        .and_then(|builder| builder.interface(MANAGER_IFACE))
        .and_then(|builder| builder.build(&(&active,)))
        .map_err(Error::Bus)
}

/// The same, for `Settings.Connection.Update`. Nothing in this crate sends this one.
pub fn passphrase_message(
    settings_path: &str,
    saved: &ConnectionSettings,
    passphrase: &str,
) -> Result<zbus::message::Message> {
    let updated = profile_with_psk(saved, passphrase)?;
    zbus::message::Message::method_call(settings_path, "Update")
        .and_then(|builder| builder.destination(NM))
        .and_then(|builder| {
            builder.interface("org.freedesktop.NetworkManager.Settings.Connection")
        })
        .and_then(|builder| builder.build(&(&updated,)))
        .map_err(Error::Bus)
}

/// The `RequestScan` message, which is the one write this crate does fire.
pub fn scan_message(device_path: &str) -> Result<zbus::message::Message> {
    let options: HashMap<String, OwnedValue> = HashMap::new();
    zbus::message::Message::method_call(device_path, "RequestScan")
        .and_then(|builder| builder.destination(NM))
        .and_then(|builder| builder.interface(WIRELESS_IFACE))
        .and_then(|builder| builder.build(&(&options,)))
        .map_err(Error::Bus)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ap::Security;

    /// zvariant renders a multi-argument body as a struct, and on the wire a top-level
    /// struct and a flat argument list are the same bytes. Stripping that rendering
    /// leaves the string `busctl --system introspect` prints for the method, which is
    /// what these tests are actually pinned to.
    fn wire_signature(message: &zbus::message::Message) -> String {
        let rendered = message.body().signature().to_string();
        rendered
            .strip_prefix('(')
            .and_then(|inner| inner.strip_suffix(')'))
            .unwrap_or(&rendered)
            .to_owned()
    }

    fn toursanak() -> AccessPoint {
        AccessPoint {
            path: "/org/freedesktop/NetworkManager/AccessPoint/485".into(),
            ssid: Ssid::new(b"Toursanak".to_vec()),
            strength: 94,
            frequency: 2457,
            hw_address: "68:CC:6E:CA:07:F0".into(),
            max_bitrate: 130000,
            bandwidth: 20,
            security: Security {
                flags: 1,
                wpa: 332,
                rsn: 332,
            },
            last_seen: 15238,
            active: true,
        }
    }

    const WLAN0: &str = "/org/freedesktop/NetworkManager/Devices/2";

    #[test]
    fn the_debounce_is_the_power_saving_multiplier_applied_to_the_window() {
        assert_eq!(PollRate::NORMAL.interval(DEBOUNCE_BASE), DEBOUNCE_BASE);
        assert_eq!(
            PollRate::SAVING.interval(DEBOUNCE_BASE),
            Duration::from_millis(200)
        );
    }

    /// Never sent. What is asserted is the wire form: destination, path, member and a
    /// body of `a{sa{sv}}oo`, which is what `nmcli dev wifi connect` produces.
    #[test]
    fn the_connect_call_is_built_the_way_the_nmcli_line_it_replaces_is() {
        let message = connect_message(WLAN0, &toursanak(), Some("hunter2")).unwrap();
        let header = message.header();

        assert_eq!(header.path().unwrap().as_str(), NM_PATH);
        assert_eq!(header.interface().unwrap(), MANAGER_IFACE);
        assert_eq!(header.member().unwrap(), "AddAndActivateConnection");
        assert_eq!(header.destination().unwrap(), NM);
        // org.freedesktop.NetworkManager.AddAndActivateConnection, as introspected on
        // this seat: a{sa{sv}}oo in, oo out.
        assert_eq!(wire_signature(&message), "a{sa{sv}}oo");

        let body = message.body();
        let (profile, device, specific) = body
            .deserialize::<(ConnectionSettings, ObjectPath<'_>, ObjectPath<'_>)>()
            .unwrap();
        assert_eq!(device.as_str(), WLAN0);
        assert_eq!(
            specific.as_str(),
            "/org/freedesktop/NetworkManager/AccessPoint/485"
        );
        let ssid = profile.get("802-11-wireless").unwrap().get("ssid").unwrap();
        assert_eq!(ssid.to_string(), Value::from(b"Toursanak".to_vec()).to_string());
    }

    #[test]
    fn the_disconnect_call_names_the_active_connection_object_and_nothing_else() {
        let message =
            disconnect_message("/org/freedesktop/NetworkManager/ActiveConnection/25").unwrap();
        let header = message.header();

        assert_eq!(header.member().unwrap(), "DeactivateConnection");
        assert_eq!(header.interface().unwrap(), MANAGER_IFACE);
        assert_eq!(wire_signature(&message), "o");
        assert_eq!(
            message
                .body()
                .deserialize::<ObjectPath<'_>>()
                .unwrap()
                .as_str(),
            "/org/freedesktop/NetworkManager/ActiveConnection/25"
        );
    }

    /// The call the stop conditions forbid firing, so this is the only place its shape
    /// is ever established.
    #[test]
    fn the_passphrase_call_targets_the_saved_profile_and_carries_the_whole_thing() {
        let saved = ConnectionSettings::from([(
            "802-11-wireless-security".to_owned(),
            HashMap::from([(
                "key-mgmt".to_owned(),
                OwnedValue::from(zvariant::Str::from_static("wpa-psk")),
            )]),
        )]);

        let message = passphrase_message(
            "/org/freedesktop/NetworkManager/Settings/34",
            &saved,
            "a new passphrase",
        )
        .unwrap();
        let header = message.header();

        assert_eq!(
            header.path().unwrap().as_str(),
            "/org/freedesktop/NetworkManager/Settings/34"
        );
        assert_eq!(
            header.interface().unwrap(),
            "org.freedesktop.NetworkManager.Settings.Connection"
        );
        assert_eq!(header.member().unwrap(), "Update");
        assert_eq!(wire_signature(&message), "a{sa{sv}}");

        let sent = message.body().deserialize::<ConnectionSettings>().unwrap();
        let security = sent.get("802-11-wireless-security").unwrap();
        assert_eq!(
            security.get("psk").unwrap().downcast_ref::<String>().unwrap(),
            "a new passphrase"
        );
        assert_eq!(
            security
                .get("key-mgmt")
                .unwrap()
                .downcast_ref::<String>()
                .unwrap(),
            "wpa-psk"
        );
    }

    #[test]
    fn the_scan_call_carries_the_empty_options_dictionary_nmcli_sends() {
        let message = scan_message(WLAN0).unwrap();
        let header = message.header();

        assert_eq!(header.path().unwrap().as_str(), WLAN0);
        assert_eq!(header.interface().unwrap(), WIRELESS_IFACE);
        assert_eq!(header.member().unwrap(), "RequestScan");
        assert_eq!(wire_signature(&message), "a{sv}");
        assert!(message
            .body()
            .deserialize::<HashMap<String, OwnedValue>>()
            .unwrap()
            .is_empty());
    }

    #[test]
    fn a_missing_bus_name_is_unavailable_and_anything_else_stays_a_failure() {
        let absent = Error::Bus(zbus::fdo::Error::ServiceUnknown(NM.into()).into());
        assert!(matches!(unavailable(absent), Error::Unavailable(_)));

        let real = Error::Bus(zbus::fdo::Error::Failed("radio is on fire".into()).into());
        assert!(matches!(unavailable(real), Error::Bus(_)));

        assert!(matches!(
            unavailable(Error::Protocol("x".into())),
            Error::Protocol(_)
        ));
    }

    #[test]
    fn the_list_is_ordered_the_way_nmcli_prints_it_and_not_associated_first() {
        let mut state = NetworkState {
            available: true,
            ..NetworkState::default()
        };
        state.wifi.present = true;
        state.wifi.enabled = true;
        state.wifi.device_state = DeviceState::Activated;
        state.connectivity = Connectivity::Full;
        state.wifi.active_ap_path = "/ap/quiet".into();

        let mut quiet = toursanak();
        quiet.path = "/ap/quiet".into();
        quiet.strength = 20;
        quiet.active = false;
        let mut loud = toursanak();
        loud.path = "/ap/loud".into();
        loud.ssid = Ssid::new(b"D28".to_vec());
        loud.strength = 90;
        loud.active = true;

        state.wifi.networks = vec![loud, quiet];
        recompute(&mut state);

        // `nmcli -g ...,SIGNAL d w` sorts by signal alone; the associated radio at 20
        // stays below the neighbour at 90. `Network.qml:26` reorders that for display,
        // and that shaping is the consumer's, not this crate's.
        assert_eq!(state.wifi.networks[0].path, "/ap/loud");
        assert!(!state.wifi.networks[0].active);
        assert_eq!(state.wifi.networks[1].path, "/ap/quiet");
        assert!(state.wifi.networks[1].active);
        assert_eq!(state.wifi.active.as_ref().unwrap().path, "/ap/quiet");
        assert_eq!(state.wifi.status, WifiStatus::Connected);
        assert_eq!(state.network_strength(), 20);
        assert!(!state.wifi.connecting);
        assert!(state.wifi.connect_target.is_none());
    }

    #[test]
    fn a_seat_with_no_radio_reports_disabled_and_an_empty_list() {
        let mut state = NetworkState {
            available: true,
            connectivity: Connectivity::Full,
            ..NetworkState::default()
        };
        state.wifi.enabled = true;
        state.wifi.networks = vec![toursanak()];
        recompute(&mut state);

        assert_eq!(state.wifi.status, WifiStatus::Disabled);
        assert!(state.wifi.active.is_none());
    }

    #[test]
    fn the_connect_target_is_the_profile_the_radio_is_bringing_up() {
        let mut state = NetworkState {
            available: true,
            connectivity: Connectivity::Full,
            ..NetworkState::default()
        };
        state.wifi.present = true;
        state.wifi.enabled = true;
        state.wifi.device_path = WLAN0.into();
        state.wifi.device_state = DeviceState::NeedAuth;
        state.active_connections = vec![ActiveConnection {
            path: "/org/freedesktop/NetworkManager/ActiveConnection/26".into(),
            id: "B28".into(),
            uuid: String::new(),
            kind: "802-11-wireless".into(),
            state: ActiveState::Activating,
            default_route: false,
            vpn: false,
            settings_path: "/org/freedesktop/NetworkManager/Settings/35".into(),
            devices: vec![WLAN0.into()],
        }];

        recompute(&mut state);

        assert_eq!(state.wifi.status, WifiStatus::Connecting);
        assert!(state.wifi.connecting);
        assert_eq!(
            state.wifi.connect_target.as_ref().unwrap().to_lossy(),
            "B28"
        );
    }

    /// A peer that floods signals and answers one method call, which is NetworkManager
    /// during an association: every access point in range reports a strength while the
    /// device walks its states.
    async fn peers() -> (Connection, Connection) {
        let (theirs, ours) = tokio::net::UnixStream::pair().unwrap();
        let guid = zbus::Guid::generate();
        let them = tokio::spawn(async move {
            zbus::connection::Builder::unix_stream(theirs)
                .server(guid)
                .unwrap()
                .p2p()
                .auth_mechanism(zbus::AuthMechanism::Anonymous)
                .build()
                .await
                .unwrap()
        });
        let ours = zbus::connection::Builder::unix_stream(ours)
            .p2p()
            .auth_mechanism(zbus::AuthMechanism::Anonymous)
            .build()
            .await
            .unwrap();
        (them.await.unwrap(), ours)
    }

    async fn flood(conn: &Connection, count: usize) {
        let changed: HashMap<&str, Value<'_>> = HashMap::from([("Strength", Value::U8(42))]);
        let invalidated: Vec<&str> = Vec::new();
        for index in 0..count {
            conn.emit_signal(
                None::<()>,
                format!("/org/freedesktop/NetworkManager/AccessPoint/{index}"),
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                &(AP_IFACE, &changed, &invalidated),
            )
            .await
            .unwrap();
        }
    }

    /// The deadlock this seat shipped: connect to an access point, and the bar keeps
    /// drawing the state from before it, with no error to retry on. zbus reads signals
    /// and method replies on one task per connection and waits rather than drops when a
    /// stream's queue is full, so a burst arriving while `apply` is awaiting a reply
    /// wedges the connection for good. What the reply is waiting behind is a queue only
    /// the loop that is stuck in `apply` would have drained.
    #[tokio::test]
    async fn a_burst_of_signals_does_not_wedge_the_method_call_apply_is_waiting_on() {
        let (them, ours) = peers().await;

        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface("org.freedesktop.DBus.Properties")
            .unwrap()
            .build();
        let signals = MessageStream::for_match_rule(rule, &ours, Some(64)).await.unwrap();
        let (mut signals, _drain) = drain(signals);

        let answering = tokio::spawn(async move {
            let mut incoming = MessageStream::from(them.clone());
            flood(&them, 512).await;
            while let Some(Ok(message)) = incoming.next().await {
                if message.header().message_type() == zbus::message::Type::MethodCall {
                    them.reply(&message.header(), &"pong").await.unwrap();
                    return;
                }
            }
        });

        // the loop is inside `apply` here: it is not touching the stream, and the reply
        // it wants has every one of those signals in front of it
        tokio::time::sleep(Duration::from_millis(200)).await;
        let reply = tokio::time::timeout(
            Duration::from_secs(5),
            ours.call_method(
                None::<()>,
                "/probe",
                Some("org.freedesktop.DBus.Peer"),
                "Ping",
                &(),
            ),
        )
        .await
        .expect("the connection wedged: a method reply never arrived past the signal burst")
        .unwrap();
        assert_eq!(reply.body().deserialize::<String>().unwrap(), "pong");

        answering.await.unwrap();

        let mut delivered = 0;
        while signals.try_recv().is_ok() {
            delivered += 1;
        }
        assert!(delivered > 64, "the burst was dropped, not drained: {delivered}");
    }
}
