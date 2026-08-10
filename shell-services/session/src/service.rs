use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};

use futures_util::stream::{BoxStream, SelectAll, StreamExt};
use koompi_service::{Backoff, Error, PollRate, Result, Service};
use tokio::sync::{broadcast, watch};
use tokio::task::JoinHandle;
use zbus::fdo::PropertiesProxy;
use zbus::names::InterfaceName;
use zbus::proxy::CacheProperties;
use zbus::{Connection, MatchRule, MessageStream};

use crate::action::{Call, PowerAction, SessionAction};
use crate::capability::{Capabilities, Capability};
use crate::inhibit::{ActiveInhibitor, Inhibitor, Mode, What};
use crate::props::Props;
use crate::proxy::{
    ManagerProxy, SessionProxy, LOGIN1, MANAGER_IFACE, MANAGER_PATH, SEAT_IFACE, SESSION_IFACE,
};
use crate::state::{SeatInfo, SessionInfo, SessionState};
use crate::SessionConfig;

/// What logind pushes at a consumer, as opposed to what a consumer can read.
///
/// These ride a [`broadcast`] rather than the state [`watch`]: a `PrepareForSleep`
/// that arrives while a consumer is busy still has to be acted on when it gets back,
/// where a stale `LockedHint` does not.
#[derive(Debug, Clone)]
pub enum SessionEvent {
    /// True on the way down, false once the machine is back. The `hold` is present
    /// only when this service was configured to take a `delay` inhibitor; while any
    /// clone of it is alive, logind waits.
    PrepareForSleep {
        going_to_sleep: bool,
        hold: Option<DelayHold>,
    },
    PrepareForShutdown {
        shutting_down: bool,
    },
    /// logind asked this session to lock. `loginctl lock-session` sends this.
    Lock,
    Unlock,
}

/// The `delay` inhibitor, handed to every subscriber at once. logind proceeds when the
/// last clone is dropped, or when `InhibitDelayMaxUSec` runs out, whichever is first.
#[derive(Clone)]
pub struct DelayHold(Arc<std::os::fd::OwnedFd>);

impl std::fmt::Debug for DelayHold {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_tuple("DelayHold")
            .field(&std::os::fd::AsRawFd::as_raw_fd(&self.0))
            .finish()
    }
}

pub struct SessionService {
    ctx: Arc<Ctx>,
    rx: watch::Receiver<SessionState>,
    events: broadcast::Sender<SessionEvent>,
    task: JoinHandle<()>,
}

impl Service for SessionService {
    type State = SessionState;

    fn state(&self) -> SessionState {
        self.rx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<SessionState> {
        self.rx.clone()
    }
}

impl Drop for SessionService {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl SessionService {
    pub async fn connect(config: SessionConfig) -> Result<Self> {
        Self::with_connection(Connection::system().await?, config).await
    }

    pub async fn with_connection(conn: Connection, config: SessionConfig) -> Result<Self> {
        let manager = ManagerProxy::new(&conn).await?;
        let session_path = resolve_session(&manager, &config).await?;

        let ctx = Arc::new(Ctx {
            conn,
            manager,
            session_path,
            poll_factor: AtomicU32::new(config.poll_rate.factor()),
            delay: Mutex::new(None),
            config,
        });

        if let Some(why) = ctx.config.delay_sleep.clone() {
            ctx.take_delay(&why).await;
        }

        // Subscribed before the first read and before the task exists: a match rule
        // added later would silently drop every signal sent in between, and the one
        // that matters most, `PrepareForSleep(true)`, is sent exactly once.
        let wakes = wake_stream(&ctx).await?;

        let (tx, rx) = watch::channel(read(&ctx).await?);
        let (events, _) = broadcast::channel(32);
        let task = tokio::spawn(run(Arc::clone(&ctx), tx, events.clone(), wakes));

        Ok(Self {
            ctx,
            rx,
            events,
            task,
        })
    }

    /// Signals, in arrival order. Late subscribers see nothing that already happened.
    pub fn events(&self) -> broadcast::Receiver<SessionEvent> {
        self.events.subscribe()
    }

    pub fn session_path(&self) -> &str {
        &self.ctx.session_path
    }

    pub fn capabilities(&self) -> Capabilities {
        self.rx.borrow().capabilities.clone()
    }

    /// `PowerSaving.qml:33`'s multiplier, pushed in by whoever subscribes to it. This
    /// crate does not poll for state - logind pushes - so it scales the one timer
    /// there is: the capability re-read that catches a polkit policy change, which
    /// emits no signal at all.
    pub fn set_poll_rate(&self, rate: PollRate) {
        self.ctx.poll_factor.store(rate.factor(), Ordering::Relaxed);
    }

    pub fn poll_rate(&self) -> PollRate {
        self.ctx.poll_rate()
    }

    /// Take a lock and hold it for as long as the returned value lives.
    ///
    /// The replacement for `Idle.qml:53-58`, where the lock is a `sleep infinity`
    /// subprocess and releasing it is a `pkill -f` on a pattern.
    pub async fn inhibit(&self, what: What, why: &str, mode: Mode) -> Result<Inhibitor> {
        if what.is_empty() {
            return Err(Error::Protocol("an inhibitor must block something".into()));
        }
        let who = self.ctx.config.who.clone();
        let fd = self
            .ctx
            .manager
            .inhibit(&what.as_wire(), &who, why, mode.as_wire())
            .await?;
        Ok(Inhibitor::new(
            what,
            who,
            why.to_owned(),
            mode,
            std::os::fd::OwnedFd::from(fd),
        ))
    }

    /// What `systemd-inhibit --list` prints, without the subprocess.
    pub async fn list_inhibitors(&self) -> Result<Vec<ActiveInhibitor>> {
        Ok(self
            .ctx
            .manager
            .list_inhibitors()
            .await?
            .into_iter()
            .map(ActiveInhibitor::from_wire)
            .collect())
    }

    /// The call `SessionRestore` and a power menu would make, built but not sent.
    /// Pair it with [`Capabilities`] before offering it to a user.
    pub fn power_call(&self, action: PowerAction, interactive: bool) -> Call {
        Call::power(action, interactive)
    }

    pub fn session_call(&self, action: SessionAction) -> Call {
        Call::session(action, &self.ctx.session_path)
    }

    /// Ask logind to raise the lock screen: it emits `Lock` on this session, and the
    /// lock screen is what answers. Nothing here draws anything.
    pub async fn lock(&self) -> Result<()> {
        self.session_call(SessionAction::Lock)
            .send(&self.ctx.conn)
            .await
    }

    pub async fn unlock(&self) -> Result<()> {
        self.session_call(SessionAction::Unlock)
            .send(&self.ctx.conn)
            .await
    }

    /// Tell logind whether this session's lock screen is up, so `LockedHint` and
    /// `loginctl` agree with the glass.
    pub async fn set_locked_hint(&self, locked: bool) -> Result<()> {
        self.ctx
            .conn
            .call_method(
                Some(LOGIN1),
                self.ctx.session_path.as_str(),
                Some(SESSION_IFACE),
                "SetLockedHint",
                &(locked,),
            )
            .await?;
        Ok(())
    }

    /// Kills this session's scope, and with it the session leader.
    ///
    /// Under a display manager the leader is the DM's helper, so calling this while
    /// the compositor is still up is the black screen of commit `3d2957e5`. The
    /// ordering that works is in `dots/.local/bin/koompi-logout`: end the compositor,
    /// wait for the leader to exit on its own, and only sweep if it did.
    /// [`SessionInfo::leader_is_display_manager_helper`] says whether that applies
    /// here, and it does on this seat.
    pub async fn terminate_session(&self) -> Result<()> {
        self.session_call(SessionAction::Terminate)
            .send(&self.ctx.conn)
            .await
    }

    /// The one route to `PowerOff`, `Reboot`, `Suspend`, `Hibernate`, `HybridSleep`
    /// and `SuspendThenHibernate`. `interactive` lets a polkit agent prompt.
    pub async fn power(&self, action: PowerAction, interactive: bool) -> Result<()> {
        self.power_call(action, interactive)
            .send(&self.ctx.conn)
            .await
    }
}

struct Ctx {
    conn: Connection,
    manager: ManagerProxy<'static>,
    session_path: String,
    poll_factor: AtomicU32,
    /// Held only when `SessionConfig::delay_sleep` is set. Taken out on
    /// `PrepareForSleep(true)` and re-taken once the machine is back.
    delay: Mutex<Option<Arc<std::os::fd::OwnedFd>>>,
    config: SessionConfig,
}

impl Ctx {
    fn poll_rate(&self) -> PollRate {
        PollRate::new(self.poll_factor.load(Ordering::Relaxed))
    }

    async fn take_delay(&self, why: &str) {
        let held = self
            .manager
            .inhibit(
                What::SLEEP.as_wire().as_str(),
                &self.config.who,
                why,
                Mode::Delay.as_wire(),
            )
            .await
            .ok()
            .map(|fd| Arc::new(std::os::fd::OwnedFd::from(fd)));
        if let Ok(mut slot) = self.delay.lock() {
            *slot = held;
        }
    }

    fn release_delay(&self) -> Option<DelayHold> {
        self.delay.lock().ok()?.take().map(DelayHold)
    }
}

/// `XDG_SESSION_ID` first, the way every shell script here finds it, then logind's own
/// answer for this pid. A process outside logind gets `Unavailable`, not a panic.
async fn resolve_session(manager: &ManagerProxy<'_>, config: &SessionConfig) -> Result<String> {
    let id = config
        .session_id
        .clone()
        .or_else(|| std::env::var("XDG_SESSION_ID").ok())
        .filter(|id| !id.is_empty());

    if let Some(id) = id {
        if let Ok(path) = manager.get_session(&id).await {
            return Ok(path.to_string());
        }
    }

    match manager.get_session_by_pid(std::process::id()).await {
        Ok(path) => Ok(path.to_string()),
        Err(_) => Err(Error::Unavailable("a logind session".into())),
    }
}

async fn properties(conn: &Connection, path: &str, interface: &str) -> Result<Props> {
    let interface = InterfaceName::try_from(interface).map_err(zbus::Error::from)?;
    PropertiesProxy::builder(conn)
        .destination(LOGIN1)?
        .path(path.to_owned())?
        .cache_properties(CacheProperties::No)
        .build()
        .await?
        .get_all(interface)
        .await
        .map_err(|error| Error::Bus(error.into()))
}

/// Six round trips, the same six `SessionWarnings.qml:47` would need six `busctl`
/// subprocesses for. A reply logind refuses to give reads as `na` rather than sinking
/// the whole sample.
async fn capabilities(manager: &ManagerProxy<'_>) -> Capabilities {
    let read = |reply: zbus::Result<String>| match reply {
        Ok(reply) => Capability::from_reply(&reply),
        Err(_) => Capability::Na,
    };
    Capabilities {
        power_off: read(manager.can_power_off().await),
        reboot: read(manager.can_reboot().await),
        suspend: read(manager.can_suspend().await),
        hibernate: read(manager.can_hibernate().await),
        hybrid_sleep: read(manager.can_hybrid_sleep().await),
        suspend_then_hibernate: read(manager.can_suspend_then_hibernate().await),
    }
}

async fn read(ctx: &Ctx) -> Result<SessionState> {
    let session_props = properties(&ctx.conn, &ctx.session_path, SESSION_IFACE).await?;
    let session = SessionInfo::from_props(&ctx.session_path, &session_props);

    let seat = match &session.seat_path {
        Some(path) => properties(&ctx.conn, path, SEAT_IFACE)
            .await
            .ok()
            .map(|props| SeatInfo::from_props(path, &props)),
        None => None,
    };

    let manager_props = properties(&ctx.conn, MANAGER_PATH, MANAGER_IFACE).await?;

    Ok(SessionState {
        session,
        seat,
        capabilities: capabilities(&ctx.manager).await,
        preparing_for_sleep: crate::props::boolean(&manager_props, "PreparingForSleep")
            .unwrap_or(false),
        preparing_for_shutdown: crate::props::boolean(&manager_props, "PreparingForShutdown")
            .unwrap_or(false),
        block_inhibited: What::parse(
            &crate::props::string(&manager_props, "BlockInhibited").unwrap_or_default(),
        ),
        delay_inhibited: What::parse(
            &crate::props::string(&manager_props, "DelayInhibited").unwrap_or_default(),
        ),
        poll_rate: ctx.poll_rate(),
    })
}

enum Wake {
    Refresh,
    Sleep(bool),
    Shutdown(bool),
    Lock,
    Unlock,
}

async fn run(
    ctx: Arc<Ctx>,
    tx: watch::Sender<SessionState>,
    events: broadcast::Sender<SessionEvent>,
    mut wakes: SelectAll<BoxStream<'static, Wake>>,
) {
    let mut backoff = Backoff::default();
    let mut offline = false;

    loop {
        let wake = if offline {
            backoff.wait().await;
            Some(Wake::Refresh)
        } else {
            let refresh = ctx.poll_rate().interval(ctx.config.capability_refresh);
            tokio::select! {
                next = wakes.next() => match next {
                    Some(wake) => Some(wake),
                    None => return,
                },
                _ = tokio::time::sleep(refresh) => Some(Wake::Refresh),
            }
        };

        match wake {
            Some(Wake::Sleep(going_to_sleep)) => {
                let hold = going_to_sleep.then(|| ctx.release_delay()).flatten();
                let _ = events.send(SessionEvent::PrepareForSleep {
                    going_to_sleep,
                    hold,
                });
                if !going_to_sleep {
                    if let Some(why) = ctx.config.delay_sleep.clone() {
                        ctx.take_delay(&why).await;
                    }
                }
            }
            Some(Wake::Shutdown(shutting_down)) => {
                let _ = events.send(SessionEvent::PrepareForShutdown { shutting_down });
            }
            Some(Wake::Lock) => {
                let _ = events.send(SessionEvent::Lock);
            }
            Some(Wake::Unlock) => {
                let _ = events.send(SessionEvent::Unlock);
            }
            Some(Wake::Refresh) | None => {}
        }

        match read(&ctx).await {
            Ok(state) => {
                offline = false;
                backoff.reset();
                tx.send_if_modified(|current| {
                    let changed = *current != state;
                    if changed {
                        *current = state;
                    }
                    changed
                });
            }
            Err(_) => offline = true,
        }
    }
}

/// No polling: the two manager signals, this session's two, and a `PropertiesChanged`
/// rule per object. `BlockInhibited` emits change, which is what makes a capability of
/// `inhibited` correct itself the moment the shell drops its keep-awake.
async fn wake_stream(ctx: &Ctx) -> Result<SelectAll<BoxStream<'static, Wake>>> {
    let mut streams: Vec<BoxStream<'static, Wake>> = Vec::new();

    streams.push(
        ctx.manager
            .receive_prepare_for_sleep()
            .await?
            .filter_map(
                |signal| async move { signal.args().ok().map(|args| Wake::Sleep(args.start)) },
            )
            .boxed(),
    );
    streams.push(
        ctx.manager
            .receive_prepare_for_shutdown()
            .await?
            .filter_map(|signal| async move {
                signal.args().ok().map(|args| Wake::Shutdown(args.start))
            })
            .boxed(),
    );

    let session = SessionProxy::builder(&ctx.conn)
        .path(ctx.session_path.clone())?
        .build()
        .await?;
    streams.push(session.receive_lock().await?.map(|_| Wake::Lock).boxed());
    streams.push(
        session
            .receive_unlock()
            .await?
            .map(|_| Wake::Unlock)
            .boxed(),
    );

    for path in [MANAGER_PATH, ctx.session_path.as_str()] {
        streams.push(properties_changed(&ctx.conn, path).await?);
    }
    if let Ok(seat) = seat_path(&ctx.conn, &ctx.session_path).await {
        streams.push(properties_changed(&ctx.conn, &seat).await?);
    }

    Ok(futures_util::stream::select_all(streams))
}

async fn properties_changed(conn: &Connection, path: &str) -> Result<BoxStream<'static, Wake>> {
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(LOGIN1)?
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .path(path.to_owned())?
        .build();
    let stream = MessageStream::for_match_rule(rule, conn, Some(16)).await?;
    Ok(stream.map(|_| Wake::Refresh).boxed())
}

async fn seat_path(conn: &Connection, session_path: &str) -> Result<String> {
    let props = properties(conn, session_path, SESSION_IFACE).await?;
    crate::props::reference(&props, "Seat")
        .map(|(_, path)| path)
        .ok_or_else(|| Error::Unavailable("a seat".into()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    /// The capability refresh is the crate's only timer, and it takes its interval
    /// from the shell-wide multiplier rather than a constant. Nothing else here polls.
    #[test]
    fn the_only_timer_scales_with_the_power_saving_multiplier() {
        let base = Duration::from_secs(60);
        assert_eq!(PollRate::NORMAL.interval(base), base);
        assert_eq!(PollRate::SAVING.interval(base), Duration::from_secs(120));
    }
}
