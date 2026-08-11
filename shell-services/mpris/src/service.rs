//! Every player on the session bus, followed by signal alone.
//!
//! Three subscriptions and no timer: `NameOwnerChanged` under the MPRIS namespace for
//! players arriving and leaving, `PropertiesChanged` on `/org/mpris/MediaPlayer2` for
//! everything a player says about itself, and `Seeked` for the one thing
//! `PropertiesChanged` is not allowed to carry.

use std::sync::Arc;
use std::time::{Duration, Instant};

use futures_util::stream::{BoxStream, SelectAll, StreamExt};
use koompi_service::{Backoff, Error, Result, Service};
use tokio::sync::{broadcast, watch, Mutex};
use tokio::task::JoinHandle;
use zbus::fdo::{DBusProxy, PropertiesProxy};
use zbus::message::Message;
use zbus::names::InterfaceName;
use zbus::proxy::CacheProperties;
use zbus::{Connection, MatchRule, MessageStream};
use zvariant::ObjectPath;

use crate::metadata::{Metadata, Props};
use crate::player::{props, LoopStatus, PlaybackStatus, Player, PositionCursor};
use crate::priority::{choose, shadow_of, ChoiceReason};
use crate::proxy::{MediaPlayer2Proxy, PlayerProxy, PATH, PLAYER_IFACE, PREFIX, ROOT_IFACE};

const ROOT: InterfaceName<'static> = InterfaceName::from_static_str_unchecked(ROOT_IFACE);
const PLAYER: InterfaceName<'static> = InterfaceName::from_static_str_unchecked(PLAYER_IFACE);

const EVENT_CAPACITY: usize = 64;

/// A player that claims to still be inside its track by less than this is believed. A
/// gapless transition and a clock that drifted both land here; a player that stopped
/// telling the truth does not.
pub const OVERRUN_SLACK: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MprisConfig {
    /// This crate has no poll. The one wait is the retry after a player claims its bus
    /// name before it has exported the object behind it, and `PowerSaving.qml:33`
    /// stretches that like every other timer in the shell.
    pub poll_rate: koompi_service::PollRate,
}

impl Default for MprisConfig {
    fn default() -> Self {
        Self {
            poll_rate: koompi_service::PollRate::NORMAL,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct MprisState {
    pub players: Vec<Player>,
    /// The bus name of the chosen player, if there is one.
    pub active: Option<String>,
    pub reason: ChoiceReason,
    pub poll_rate: koompi_service::PollRate,
}

impl MprisState {
    pub fn player(&self, bus_name: &str) -> Option<&Player> {
        self.players.iter().find(|p| p.bus_name == bus_name)
    }

    pub fn active_player(&self) -> Option<&Player> {
        self.player(self.active.as_deref()?)
    }

    /// The players a consumer would normally draw: the shadows at
    /// `MprisController.qml:35-46` left out.
    pub fn candidates(&self) -> impl Iterator<Item = &Player> {
        self.players.iter().filter(|p| p.shadowed.is_none())
    }
}

/// What must not be missed. The state is last-value-wins, so a track that started and
/// ended between two reads would leave no trace in it.
#[derive(Debug, Clone, PartialEq)]
pub enum MprisEvent {
    PlayerAppeared(String),
    PlayerVanished(String),
    StatusChanged {
        bus_name: String,
        status: PlaybackStatus,
    },
    TrackChanged {
        bus_name: String,
        metadata: Box<Metadata>,
    },
    /// The player moved its own position. The only event that carries one.
    Seeked {
        bus_name: String,
        position_us: i64,
    },
}

pub struct MprisService {
    ctx: Arc<Ctx>,
    rx: watch::Receiver<MprisState>,
    events: broadcast::Sender<MprisEvent>,
    task: JoinHandle<()>,
}

impl Service for MprisService {
    type State = MprisState;

    fn state(&self) -> MprisState {
        self.rx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<MprisState> {
        self.rx.clone()
    }
}

impl Drop for MprisService {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl MprisService {
    pub async fn connect(config: MprisConfig) -> Result<Self> {
        Self::with_connection(Connection::session().await?, config).await
    }

    pub async fn with_connection(conn: Connection, config: MprisConfig) -> Result<Self> {
        let ctx = Arc::new(Ctx {
            conn,
            config,
            pinned: Mutex::new(None),
        });

        // Before the first read, not inside the task that drains it. A match rule added
        // later does not backfill, and half of what this crate reports happens exactly
        // once: a `Seeked`, or a player taking or dropping its name. Subscribing after
        // the read would lose whichever of those landed in the gap, and nothing repeats
        // them. Reading after subscribing can instead replay a change we already have,
        // which merges to the same state.
        let wake = wake_stream(&ctx).await?;

        let mut players = Registry::default();
        for bus_name in list_players(&ctx).await? {
            players.add(read_player(&ctx, &bus_name).await.ok());
        }
        players.reshadow();

        let (tx, rx) = watch::channel(players.state(ctx.config.poll_rate, None));
        let (events, _) = broadcast::channel(EVENT_CAPACITY);
        let task = tokio::spawn(run(Arc::clone(&ctx), tx, events.clone(), players, wake));

        Ok(Self {
            ctx,
            rx,
            events,
            task,
        })
    }

    pub fn events(&self) -> broadcast::Receiver<MprisEvent> {
        self.events.subscribe()
    }

    pub fn player(&self, bus_name: &str) -> Option<Player> {
        self.rx.borrow().player(bus_name).cloned()
    }

    pub fn active(&self) -> Option<Player> {
        self.rx.borrow().active_player().cloned()
    }

    /// `MprisController.qml:224-236`. The pin holds only while the player is still a
    /// candidate; the rule takes back over the moment it leaves.
    pub async fn pin(&self, bus_name: Option<&str>) {
        *self.ctx.pinned.lock().await = bus_name.map(ToOwned::to_owned);
    }

    pub async fn play_pause(&self, bus_name: &str) -> Result<()> {
        self.player_proxy(bus_name).await?.play_pause().await?;
        Ok(())
    }

    pub async fn play(&self, bus_name: &str) -> Result<()> {
        self.player_proxy(bus_name).await?.play().await?;
        Ok(())
    }

    pub async fn pause(&self, bus_name: &str) -> Result<()> {
        self.player_proxy(bus_name).await?.pause().await?;
        Ok(())
    }

    pub async fn stop(&self, bus_name: &str) -> Result<()> {
        self.player_proxy(bus_name).await?.stop().await?;
        Ok(())
    }

    pub async fn next(&self, bus_name: &str) -> Result<()> {
        self.player_proxy(bus_name).await?.next().await?;
        Ok(())
    }

    pub async fn previous(&self, bus_name: &str) -> Result<()> {
        self.player_proxy(bus_name).await?.previous().await?;
        Ok(())
    }

    /// Relative, in microseconds, negative to go back.
    pub async fn seek(&self, bus_name: &str, offset_us: i64) -> Result<()> {
        self.player_proxy(bus_name).await?.seek(offset_us).await?;
        Ok(())
    }

    /// Absolute. The player ignores it unless `track_id` is still what is loaded, which
    /// is what stops a seek issued against the previous track from landing on this one.
    pub async fn set_position(&self, bus_name: &str, track_id: &str, position_us: i64) -> Result<()> {
        let path = ObjectPath::try_from(track_id)
            .map_err(|_| Error::Protocol(format!("{track_id} is not an object path")))?;
        self.player_proxy(bus_name)
            .await?
            .set_position(&path, position_us)
            .await?;
        Ok(())
    }

    /// The same, against whatever track the player is holding now.
    pub async fn seek_to(&self, bus_name: &str, position_us: i64) -> Result<()> {
        let track_id = self
            .player(bus_name)
            .and_then(|player| player.metadata.track_id)
            .ok_or_else(|| Error::Unavailable(format!("a track id on {bus_name}")))?;
        self.set_position(bus_name, &track_id, position_us).await
    }

    pub async fn set_volume(&self, bus_name: &str, volume: f64) -> Result<()> {
        self.player_proxy(bus_name)
            .await?
            .set_volume(volume.clamp(0.0, 1.0))
            .await?;
        Ok(())
    }

    pub async fn set_loop_status(&self, bus_name: &str, status: LoopStatus) -> Result<()> {
        self.player_proxy(bus_name)
            .await?
            .set_loop_status(status.as_str())
            .await?;
        Ok(())
    }

    pub async fn set_shuffle(&self, bus_name: &str, shuffle: bool) -> Result<()> {
        self.player_proxy(bus_name).await?.set_shuffle(shuffle).await?;
        Ok(())
    }

    pub async fn set_rate(&self, bus_name: &str, rate: f64) -> Result<()> {
        self.player_proxy(bus_name).await?.set_rate(rate).await?;
        Ok(())
    }

    pub async fn raise(&self, bus_name: &str) -> Result<()> {
        self.root_proxy(bus_name).await?.raise().await?;
        Ok(())
    }

    pub async fn quit(&self, bus_name: &str) -> Result<()> {
        self.root_proxy(bus_name).await?.quit().await?;
        Ok(())
    }

    /// One `Get` on demand, for a consumer that wants the player's own answer rather than
    /// the interpolated one. This is what replaces `MprisController.qml:153-172`: the same
    /// question, asked over the bus instead of through a `playerctl` subprocess, and asked
    /// when someone wants to know instead of every three seconds.
    pub async fn read_position(&self, bus_name: &str) -> Result<i64> {
        read_position(&self.ctx, bus_name)
            .await
            .ok_or_else(|| Error::Unavailable(format!("Position on {bus_name}")))
    }

    async fn player_proxy(&self, bus_name: &str) -> Result<PlayerProxy<'_>> {
        Ok(PlayerProxy::builder(&self.ctx.conn)
            .destination(bus_name.to_owned())?
            .cache_properties(CacheProperties::No)
            .build()
            .await?)
    }

    async fn root_proxy(&self, bus_name: &str) -> Result<MediaPlayer2Proxy<'_>> {
        Ok(MediaPlayer2Proxy::builder(&self.ctx.conn)
            .destination(bus_name.to_owned())?
            .cache_properties(CacheProperties::No)
            .build()
            .await?)
    }
}

struct Ctx {
    conn: Connection,
    config: MprisConfig,
    pinned: Mutex<Option<String>>,
}

/// The players, their cached property maps, and the one decode path they all go through.
///
/// `Position` never enters a cache: it is the property the spec exempts from
/// `PropertiesChanged`, so a stored copy is stale by definition. It lives in the cursor.
#[derive(Default)]
struct Registry {
    entries: Vec<Entry>,
}

struct Entry {
    root: Props,
    player_props: Props,
    player: Player,
}

impl Registry {
    fn add(&mut self, entry: Option<Entry>) {
        if let Some(entry) = entry {
            self.remove(&entry.player.bus_name);
            self.entries.push(entry);
        }
    }

    fn remove(&mut self, bus_name: &str) -> bool {
        let before = self.entries.len();
        self.entries.retain(|e| e.player.bus_name != bus_name);
        before != self.entries.len()
    }

    fn by_owner(&mut self, owner: &str) -> Option<&mut Entry> {
        self.entries.iter_mut().find(|e| e.player.owner == owner)
    }

    fn has(&self, bus_name: &str) -> bool {
        self.entries.iter().any(|e| e.player.bus_name == bus_name)
    }

    /// A browser bus becomes a shadow the moment plasma-browser-integration appears and
    /// stops being one when it leaves, so this is recomputed over the whole set rather
    /// than decided once per player.
    fn reshadow(&mut self) {
        let names: Vec<String> = self.entries.iter().map(|e| e.player.bus_name.clone()).collect();
        for entry in &mut self.entries {
            entry.player.shadowed = shadow_of(&entry.player.bus_name, &names);
        }
    }

    fn state(&self, poll_rate: koompi_service::PollRate, pinned: Option<&str>) -> MprisState {
        let players: Vec<Player> = self.entries.iter().map(|e| e.player.clone()).collect();
        let (index, reason) = choose(&players, pinned);
        MprisState {
            active: index.map(|i| players[i].bus_name.clone()),
            reason,
            players,
            poll_rate,
        }
    }
}

async fn list_players(ctx: &Ctx) -> Result<Vec<String>> {
    let names = DBusProxy::new(&ctx.conn)
        .await?
        .list_names()
        .await
        .map_err(|error| Error::Bus(error.into()))?;

    Ok(names
        .into_iter()
        .map(|name| name.to_string())
        .filter(|name| name.starts_with(PREFIX))
        .collect())
}

async fn properties<'a>(ctx: &'a Ctx, bus_name: &str) -> Result<PropertiesProxy<'a>> {
    Ok(PropertiesProxy::builder(&ctx.conn)
        .destination(bus_name.to_owned())?
        .path(PATH)?
        .cache_properties(CacheProperties::No)
        .build()
        .await?)
}

async fn read_player(ctx: &Ctx, bus_name: &str) -> Result<Entry> {
    let props = properties(ctx, bus_name).await?;
    let root = props.get_all(ROOT).await.unwrap_or_default();
    let mut player_props = props
        .get_all(PLAYER)
        .await
        .map_err(|error| Error::Bus(error.into()))?;

    if player_props.is_empty() {
        return Err(Error::Protocol(format!(
            "{bus_name} exports no {PLAYER_IFACE} properties"
        )));
    }

    let owner = owner_of(ctx, bus_name).await;
    let player = Player::from_props(bus_name.to_owned(), owner, &root, &player_props, None);
    player_props.remove("Position");

    Ok(Entry {
        root,
        player_props,
        player,
    })
}

/// A player claims its well-known name before it exports the object behind it; Chromium
/// reliably does. This is the crate's only wait, and it ends as soon as the object is
/// there rather than running on a schedule.
async fn read_player_when_ready(ctx: &Ctx, bus_name: &str) -> Option<Entry> {
    let rate = ctx.config.poll_rate;
    let mut backoff = Backoff::new(
        rate.interval(Duration::from_millis(120)),
        rate.interval(Duration::from_millis(500)),
    );
    for attempt in 0..4 {
        match read_player(ctx, bus_name).await {
            Ok(entry) => return Some(entry),
            Err(_) if attempt < 3 => backoff.wait().await,
            Err(_) => return None,
        }
    }
    None
}

/// Signals carry the unique name, and a player is discovered under its well-known one.
async fn owner_of(ctx: &Ctx, bus_name: &str) -> String {
    let Ok(proxy) = DBusProxy::new(&ctx.conn).await else {
        return bus_name.to_owned();
    };
    match zbus::names::BusName::try_from(bus_name) {
        Ok(name) => proxy
            .get_name_owner(name)
            .await
            .map(|owner| owner.to_string())
            .unwrap_or_else(|_| bus_name.to_owned()),
        Err(_) => bus_name.to_owned(),
    }
}

async fn read_position(ctx: &Ctx, bus_name: &str) -> Option<i64> {
    let value = properties(ctx, bus_name)
        .await
        .ok()?
        .get(PLAYER, "Position")
        .await
        .ok()?;
    props::number(&value)
}

enum Wake {
    /// A well-known MPRIS name changed hands: `(name, new owner)`.
    Owner(String, String),
    /// `(sender, interface, changed, invalidated)`.
    Properties(String, String, Props, Vec<String>),
    /// `(sender, position)`.
    Seeked(String, i64),
}

/// Takes the wake stream rather than opening one, so the subscription cannot drift back
/// to after the first read: by the time this runs, every rule is already installed and
/// anything that arrived in the meantime is queued in front of it.
async fn run(
    ctx: Arc<Ctx>,
    tx: watch::Sender<MprisState>,
    events: broadcast::Sender<MprisEvent>,
    mut registry: Registry,
    mut wake: SelectAll<BoxStream<'static, Wake>>,
) {
    while let Some(wake) = wake.next().await {
        match wake {
            Wake::Owner(bus_name, owner) => {
                if owner.is_empty() {
                    if registry.remove(&bus_name) {
                        let _ = events.send(MprisEvent::PlayerVanished(bus_name));
                    }
                } else {
                    registry.add(read_player_when_ready(&ctx, &bus_name).await);
                    if registry.has(&bus_name) {
                        let _ = events.send(MprisEvent::PlayerAppeared(bus_name));
                    }
                }
                registry.reshadow();
            }
            Wake::Properties(sender, interface, changed, invalidated) => {
                apply_properties(&ctx, &mut registry, &events, &sender, &interface, changed, invalidated)
                    .await;
            }
            Wake::Seeked(sender, position_us) => {
                let Some(entry) = registry.by_owner(&sender) else {
                    continue;
                };
                entry.player.position = PositionCursor::new(
                    position_us.max(0),
                    entry.player.rate,
                    entry.player.is_playing(),
                );
                entry.player.last_active = Instant::now();
                let _ = events.send(MprisEvent::Seeked {
                    bus_name: entry.player.bus_name.clone(),
                    position_us,
                });
            }
        }
        publish(&ctx, &tx, &registry).await;
    }
}

/// Merge what the player said into its cached maps and rebuild it from the one decode
/// path, rather than hand-patching a field per property name.
async fn apply_properties(
    ctx: &Ctx,
    registry: &mut Registry,
    events: &broadcast::Sender<MprisEvent>,
    sender: &str,
    interface: &str,
    changed: Props,
    invalidated: Vec<String>,
) {
    let Some(entry) = registry.by_owner(sender) else {
        return;
    };

    let cache = match interface {
        ROOT_IFACE => &mut entry.root,
        PLAYER_IFACE => &mut entry.player_props,
        _ => return,
    };
    // `Position` is never cached; if a player sends it anyway it is an anchor, not state.
    let announced_position = changed.get("Position").and_then(|value| props::number(value));
    for (key, value) in changed {
        if key == "Position" {
            continue;
        }
        cache.insert(key, value);
    }
    for key in &invalidated {
        cache.remove(key);
    }

    let before = entry.player.clone();
    let mut player = Player::from_props(
        before.bus_name.clone(),
        before.owner.clone(),
        &entry.root,
        &entry.player_props,
        before.shadowed,
    );

    let status_changed = player.playback_status != before.playback_status;
    let track_changed = crate::metadata::track_moved(&before.metadata, &player.metadata);
    let rate_changed = player.rate != before.rate;

    // The anchor is re-read exactly when something invalidated it, which is the whole of
    // the poll `MprisController.qml:174-183` runs: a status change, a rate change or a
    // new track. In between, interpolation is exact.
    let invalidated = status_changed || track_changed || rate_changed;
    let bus_name = before.bus_name.clone();
    let fresh = match announced_position {
        Some(position) => Some(position),
        None if invalidated => read_position(ctx, &bus_name).await,
        None => None,
    };

    player.position = next_cursor(
        before.position,
        fresh,
        invalidated,
        player.rate,
        player.is_playing(),
    );
    player.last_active = if status_changed || track_changed {
        Instant::now()
    } else {
        before.last_active
    };

    let metadata = player.metadata.clone();
    let status = player.playback_status;
    let Some(entry) = registry.by_owner(sender) else {
        return;
    };
    entry.player = player;

    if status_changed {
        let _ = events.send(MprisEvent::StatusChanged {
            bus_name: bus_name.clone(),
            status,
        });
    }
    if track_changed {
        let _ = events.send(MprisEvent::TrackChanged {
            bus_name,
            metadata: Box::new(metadata),
        });
    }
}

/// The anchor after a property change.
///
/// A change that touched nothing playback moves on leaves it exactly as it was: re-timing
/// an anchor that is still true would wake every subscriber and round the position again
/// for no reason. A player that will not answer `Position` still has to stop moving when
/// it pauses, so the interpolated value is frozen in place rather than left advancing.
fn next_cursor(
    old: PositionCursor,
    read: Option<i64>,
    invalidated: bool,
    rate: f64,
    advancing: bool,
) -> PositionCursor {
    if read.is_none() && !invalidated {
        return old;
    }
    let position = read.unwrap_or_else(|| old.at(Instant::now()));
    PositionCursor::new(position.max(0), rate, advancing)
}

async fn publish(ctx: &Ctx, tx: &watch::Sender<MprisState>, registry: &Registry) {
    let pinned = ctx.pinned.lock().await.clone();
    let state = registry.state(ctx.config.poll_rate, pinned.as_deref());
    tx.send_if_modified(|current| {
        let changed = *current != state;
        if changed {
            *current = state;
        }
        changed
    });
}

/// Three rules, none of them per player: a player that appears after start needs nothing
/// added and nothing removed when it goes.
async fn wake_stream(ctx: &Ctx) -> Result<SelectAll<BoxStream<'static, Wake>>> {
    let owners = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.DBus")?
        .member("NameOwnerChanged")?
        .arg0ns("org.mpris.MediaPlayer2")?
        .build();

    // Both MPRIS interfaces live on the one path, so one rule covers Identity as well as
    // PlaybackStatus.
    let props = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .path(PATH)?
        .build();

    let seeked = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface(PLAYER)?
        .member("Seeked")?
        .build();

    let sender_of = |message: &Message| {
        message
            .header()
            .sender()
            .map(|sender| sender.to_string())
            .unwrap_or_default()
    };

    let streams: Vec<BoxStream<'static, Wake>> = vec![
        stream(ctx, owners)
            .await?
            .filter_map(|message| async move {
                let (name, _old, new): (String, String, String) =
                    message.body().deserialize().ok()?;
                name.starts_with(PREFIX).then_some(Wake::Owner(name, new))
            })
            .boxed(),
        stream(ctx, props)
            .await?
            .filter_map(move |message| {
                let sender = sender_of(&message);
                async move {
                    let (interface, changed, invalidated): (String, Props, Vec<String>) =
                        message.body().deserialize().ok()?;
                    Some(Wake::Properties(sender, interface, changed, invalidated))
                }
            })
            .boxed(),
        stream(ctx, seeked)
            .await?
            .filter_map(move |message| {
                let sender = sender_of(&message);
                async move {
                    let position: i64 = message.body().deserialize().ok()?;
                    Some(Wake::Seeked(sender, position))
                }
            })
            .boxed(),
    ];

    Ok(futures_util::stream::select_all(streams))
}

async fn stream(ctx: &Ctx, rule: MatchRule<'static>) -> Result<impl StreamExt<Item = Message>> {
    Ok(MessageStream::for_match_rule(rule, &ctx.conn, Some(32))
        .await?
        .filter_map(|message| async move { message.ok() }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pause_freezes_the_interpolated_position_even_when_the_player_will_not_answer() {
        let playing = PositionCursor::new(10_000_000, 1.0, true);
        let at_pause = playing.at(Instant::now());

        let paused = next_cursor(playing, None, true, 1.0, false);

        assert!(!paused.advancing);
        assert!((paused.position_us - at_pause).abs() < 50_000);
        // And it stays there: no clock moves a paused cursor.
        assert_eq!(
            paused.at(paused.read_at + Duration::from_secs(30)),
            paused.position_us
        );
    }

    #[test]
    fn a_player_that_answers_position_wins_over_the_interpolation() {
        let drifted = PositionCursor::new(10_000_000, 1.0, true);
        let anchored = next_cursor(drifted, Some(3_000_000), true, 1.0, true);

        assert_eq!(anchored.position_us, 3_000_000);
        assert!(anchored.advancing);
    }

    /// Chromium announces a volume change several times a second on some pages. None of
    /// those touch playback, so none of them may move the anchor or wake a subscriber.
    #[test]
    fn a_property_change_that_touches_nothing_leaves_the_anchor_exactly_as_it_was() {
        let playing = PositionCursor::new(10_000_000, 1.0, true);
        let after = next_cursor(playing, None, false, 1.0, true);

        assert_eq!(after, playing);
        assert_eq!(after.read_at, playing.read_at);
    }

    #[test]
    fn a_negative_position_is_clamped_rather_than_carried() {
        let cursor = next_cursor(PositionCursor::new(0, 1.0, false), Some(-42), true, 1.0, false);
        assert_eq!(cursor.position_us, 0);
    }

    /// The write side against a real player, ignored by default and gated on being handed
    /// one by name:
    ///
    /// ```text
    /// KOOMPI_MPRIS_PLAYER=org.mpris.MediaPlayer2.chromium.instance123 \
    ///   cargo test -p koompi-mpris -- --ignored --nocapture exercises_the_controls
    /// ```
    ///
    /// The env var is the stop condition written down where it can be enforced: without
    /// it this touches nothing, and it will not go looking for a player to drive. Every
    /// setting it changes is put back before it returns.
    #[tokio::test]
    #[ignore = "drives a live player; needs KOOMPI_MPRIS_PLAYER"]
    async fn exercises_the_controls_against_the_player_it_was_handed() {
        let Ok(bus_name) = std::env::var("KOOMPI_MPRIS_PLAYER") else {
            panic!("set KOOMPI_MPRIS_PLAYER to the bus name of a player you started");
        };

        let mpris = MprisService::connect(MprisConfig::default()).await.unwrap();
        let settle = || tokio::time::sleep(Duration::from_millis(700));
        let player = || mpris.player(&bus_name).expect("that player is not on the bus");

        let before = player();
        println!(
            "before  status={} position={} volume={:?} loop={:?} shuffle={:?}",
            before.playback_status.as_str(),
            before.position_now(),
            before.volume,
            before.loop_status,
            before.shuffle
        );

        mpris.play_pause(&bus_name).await.unwrap();
        settle().await;
        let toggled = player();
        println!("PlayPause -> {}", toggled.playback_status.as_str());
        assert_ne!(toggled.playback_status, before.playback_status);

        mpris.play_pause(&bus_name).await.unwrap();
        settle().await;
        assert_eq!(player().playback_status, before.playback_status);

        let anchor = player().position.position_us;
        mpris.seek(&bus_name, 5_000_000).await.unwrap();
        settle().await;
        let seeked = player();
        println!("Seek +5s -> anchor {} (was {anchor})", seeked.position.position_us);
        assert!(seeked.position.position_us > anchor + 4_000_000);

        mpris.seek_to(&bus_name, anchor).await.unwrap();
        settle().await;
        println!("SetPosition back -> anchor {}", player().position.position_us);

        if let Some(volume) = before.volume {
            mpris.set_volume(&bus_name, 0.42).await.unwrap();
            settle().await;
            println!("Volume -> {:?}", player().volume);
            mpris.set_volume(&bus_name, volume).await.unwrap();
            settle().await;
            println!("Volume restored -> {:?}", player().volume);
        }

        if let Some(status) = before.loop_status {
            let other = if status == LoopStatus::Track {
                LoopStatus::Playlist
            } else {
                LoopStatus::Track
            };
            mpris.set_loop_status(&bus_name, other).await.unwrap();
            settle().await;
            println!("LoopStatus -> {:?}", player().loop_status);
            mpris.set_loop_status(&bus_name, status).await.unwrap();
            settle().await;
            println!("LoopStatus restored -> {:?}", player().loop_status);
            assert_eq!(player().loop_status, Some(status));
        }

        if let Some(shuffle) = before.shuffle {
            mpris.set_shuffle(&bus_name, !shuffle).await.unwrap();
            settle().await;
            println!("Shuffle -> {:?}", player().shuffle);
            mpris.set_shuffle(&bus_name, shuffle).await.unwrap();
            settle().await;
            println!("Shuffle restored -> {:?}", player().shuffle);
            assert_eq!(player().shuffle, Some(shuffle));
        }

        let after = player();
        assert_eq!(after.playback_status, before.playback_status);
        assert_eq!(after.volume, before.volume);
        assert_eq!(after.loop_status, before.loop_status);
        assert_eq!(after.shuffle, before.shuffle);
        println!("restored status={} volume={:?}", after.playback_status.as_str(), after.volume);
    }
}
