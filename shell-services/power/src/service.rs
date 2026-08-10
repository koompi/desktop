use std::sync::Arc;

use futures_util::stream::{BoxStream, SelectAll, StreamExt};
use koompi_service::{Backoff, Error, PollRate, Result, Service};
use tokio::sync::watch;
use tokio::task::JoinHandle;
use zbus::fdo::PropertiesProxy;
use zbus::names::InterfaceName;
use zbus::proxy::CacheProperties;
use zbus::{Connection, MatchRule, MessageStream};
use zvariant::OwnedObjectPath;

use crate::battery::{self, Battery};
use crate::profiles::{self, Profile, Profiles};
use crate::props::{self, Props};
use crate::proxy::{DeviceProxy, PowerProfilesProxy, UPowerProxy};
use crate::PowerConfig;

const UPOWER: &str = "org.freedesktop.UPower";
const UPOWER_PATH: &str = "/org/freedesktop/UPower";
const DEVICE_IFACE: InterfaceName<'static> =
    InterfaceName::from_static_str_unchecked("org.freedesktop.UPower.Device");
const MANAGER_IFACE: InterfaceName<'static> = InterfaceName::from_static_str_unchecked(UPOWER);

const PPD: &str = "org.freedesktop.UPower.PowerProfiles";
const PPD_PATH: &str = "/org/freedesktop/UPower/PowerProfiles";
const PPD_IFACE: InterfaceName<'static> = InterfaceName::from_static_str_unchecked(PPD);

/// Everything `Battery.qml`, `ChargeLimit.qml` and `PowerSaving.qml` publish between
/// them, as one value: a consumer that fell behind sees the seat as it is now.
#[derive(Debug, Clone, PartialEq)]
pub struct PowerState {
    /// UPower's own `OnBattery`, which stays right at 100% on AC where
    /// `Battery.qml:15` reads plugged-in off the charge state and cannot.
    pub on_battery: bool,
    pub plugged_in: bool,
    /// UPower's aggregate, the device `Battery.qml` binds to.
    pub display: Option<Battery>,
    pub batteries: Vec<Battery>,
    pub profiles: Option<Profiles>,
    pub poll_rate: PollRate,
}

impl PowerState {
    /// The real pack where there is one, so `native_path`, cycle count and the
    /// thresholds are populated; the aggregate otherwise.
    pub fn primary(&self) -> Option<&Battery> {
        self.batteries.first().or(self.display.as_ref())
    }
}

pub struct PowerService {
    ctx: Arc<Ctx>,
    rx: watch::Receiver<PowerState>,
    task: JoinHandle<()>,
}

impl Service for PowerService {
    type State = PowerState;

    fn state(&self) -> PowerState {
        self.rx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<PowerState> {
        self.rx.clone()
    }
}

impl Drop for PowerService {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl PowerService {
    pub async fn connect(config: PowerConfig) -> Result<Self> {
        Self::with_connection(Connection::system().await?, config).await
    }

    pub async fn with_connection(conn: Connection, config: PowerConfig) -> Result<Self> {
        let upower = UPowerProxy::new(&conn).await?;
        let display = upower.get_display_device().await?;
        let ppd = open_power_profiles(&conn, config.power_profiles).await;

        let ctx = Arc::new(Ctx {
            conn,
            upower,
            display,
            ppd,
            config,
        });

        let (tx, rx) = watch::channel(read(&ctx).await?);
        let task = tokio::spawn(run(Arc::clone(&ctx), tx));

        Ok(Self { ctx, rx, task })
    }

    pub fn poll_rate(&self) -> PollRate {
        self.rx.borrow().poll_rate
    }

    /// A seat with no battery is a working seat, so it answers `Unavailable` rather
    /// than failing the whole service.
    pub fn battery(&self) -> Result<Battery> {
        self.rx
            .borrow()
            .primary()
            .cloned()
            .ok_or_else(|| Error::Unavailable("battery".into()))
    }

    pub fn profiles(&self) -> Result<Profiles> {
        match self.rx.borrow().profiles.clone() {
            Some(profiles) => Ok(profiles),
            None => profiles::unavailable(),
        }
    }

    /// The native replacement for the `busctl call` at `ChargeLimit.qml:54`.
    pub async fn set_charge_threshold_enabled(&self, enabled: bool) -> Result<()> {
        let battery = self.battery()?;
        if !battery.threshold.supported {
            return Err(Error::Unavailable("charge threshold".into()));
        }

        let path = battery::battery_object_path(&battery.native_path)?;
        DeviceProxy::builder(&self.ctx.conn)
            .path(path)?
            .cache_properties(CacheProperties::No)
            .build()
            .await?
            .enable_charge_threshold(enabled)
            .await?;
        Ok(())
    }

    /// `PowerSaving.qml:48` swaps the profile on the AC/battery edge. That policy
    /// belongs to whoever owns the user's preference, not to this crate; all that
    /// lives here is the write itself.
    pub async fn set_profile(&self, profile: Profile) -> Result<()> {
        if self.ctx.ppd.is_none() {
            return profiles::unavailable();
        }
        PowerProfilesProxy::new(&self.ctx.conn)
            .await?
            .set_active_profile(profile.as_str())
            .await?;
        Ok(())
    }
}

struct Ctx {
    conn: Connection,
    upower: UPowerProxy<'static>,
    display: OwnedObjectPath,
    ppd: Option<PropertiesProxy<'static>>,
    config: PowerConfig,
}

/// `PowerSaving.qml:53` holds the daemon at arm's length while the feature is off so
/// a shell that never uses profiles never activates it. `enable` is that gate; past
/// it, a daemon that is simply not installed is absent, not an error.
async fn open_power_profiles(conn: &Connection, enable: bool) -> Option<PropertiesProxy<'static>> {
    if !enable {
        return None;
    }
    let proxy = properties_proxy(conn, PPD, PPD_PATH).await.ok()?;
    proxy.get_all(PPD_IFACE).await.ok()?;
    Some(proxy)
}

async fn properties_proxy(
    conn: &Connection,
    destination: &str,
    path: &str,
) -> zbus::Result<PropertiesProxy<'static>> {
    PropertiesProxy::builder(conn)
        .destination(destination.to_owned())?
        .path(path.to_owned())?
        .cache_properties(CacheProperties::No)
        .build()
        .await
}

async fn get_all(conn: &Connection, path: &str, interface: InterfaceName<'_>) -> Result<Props> {
    properties_proxy(conn, UPOWER, path)
        .await?
        .get_all(interface)
        .await
        .map_err(|error| Error::Bus(error.into()))
}

async fn read(ctx: &Ctx) -> Result<PowerState> {
    let manager = get_all(&ctx.conn, UPOWER_PATH, MANAGER_IFACE).await?;
    let on_battery = props::boolean(&manager, "OnBattery").unwrap_or(false);

    let display_props = get_all(&ctx.conn, ctx.display.as_str(), DEVICE_IFACE).await?;
    let display = battery::is_laptop_battery(&display_props)
        .then(|| Battery::from_props(ctx.display.as_str(), &display_props, &ctx.config));

    let mut batteries = Vec::new();
    for path in ctx.upower.enumerate_devices().await? {
        let device = get_all(&ctx.conn, path.as_str(), DEVICE_IFACE).await?;
        if battery::is_laptop_battery(&device) {
            batteries.push(Battery::from_props(path.as_str(), &device, &ctx.config));
        }
    }

    let profiles = match &ctx.ppd {
        Some(proxy) => proxy
            .get_all(PPD_IFACE)
            .await
            .ok()
            .map(|p| Profiles::from_props(&p)),
        None => None,
    };

    Ok(PowerState {
        on_battery,
        plugged_in: !on_battery,
        display,
        batteries,
        profiles,
        poll_rate: poll_rate_for(&ctx.config, on_battery),
    })
}

/// `PowerSaving.qml:31`: one multiplier for the whole shell, and this is where it is
/// born. Every other crate's timers take their rate from the value published here.
fn poll_rate_for(config: &PowerConfig, on_battery: bool) -> PollRate {
    if config.save_on_battery && on_battery {
        PollRate::SAVING
    } else {
        PollRate::NORMAL
    }
}

async fn run(ctx: Arc<Ctx>, tx: watch::Sender<PowerState>) {
    let Ok(mut wake) = wake_stream(&ctx).await else {
        return;
    };
    let mut backoff = Backoff::default();
    let mut offline = false;

    loop {
        if offline {
            backoff.wait().await;
        } else if wake.next().await.is_none() {
            return;
        }

        match read(&ctx).await {
            Ok(state) => {
                offline = false;
                backoff.reset();
                // UPower repeats `UpdateTime` on every refresh whether or not
                // anything a consumer can see moved.
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

/// One rule per sender rather than one per object: a battery hot-added after start,
/// or a USB-C supply appearing, wakes us without a subscription of its own.
async fn wake_stream(ctx: &Ctx) -> Result<SelectAll<BoxStream<'static, ()>>> {
    let mut senders = vec![UPOWER];
    if ctx.ppd.is_some() {
        senders.push(PPD);
    }

    let mut streams = Vec::new();
    for sender in senders {
        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .sender(sender)?
            .build();
        let stream = MessageStream::for_match_rule(rule, &ctx.conn, Some(16)).await?;
        streams.push(stream.map(|_| ()).boxed());
    }

    Ok(futures_util::stream::select_all(streams))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_poll_multiplier_follows_the_seat_off_ac_and_only_when_asked_to() {
        let saving = PowerConfig::default();
        assert!(saving.save_on_battery);
        assert_eq!(poll_rate_for(&saving, true), PollRate::SAVING);
        assert_eq!(poll_rate_for(&saving, false), PollRate::NORMAL);

        let always = PowerConfig {
            save_on_battery: false,
            ..PowerConfig::default()
        };
        assert_eq!(poll_rate_for(&always, true), PollRate::NORMAL);
    }

    /// `EnableChargeThreshold` is never called against this seat, so the wire form is
    /// what gets checked: it must be the message
    /// `busctl call org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_BAT0
    /// org.freedesktop.UPower.Device EnableChargeThreshold b true` puts on the bus.
    #[test]
    fn the_threshold_call_is_built_the_way_the_busctl_line_it_replaces_is() {
        let path = battery::battery_object_path("BAT0").unwrap();
        let message = zbus::message::Message::method_call(&path, "EnableChargeThreshold")
            .unwrap()
            .destination(UPOWER)
            .unwrap()
            .interface(DEVICE_IFACE)
            .unwrap()
            .build(&(true,))
            .unwrap();

        let header = message.header();
        assert_eq!(
            header.path().unwrap().as_str(),
            "/org/freedesktop/UPower/devices/battery_BAT0"
        );
        assert_eq!(header.interface().unwrap(), &DEVICE_IFACE);
        assert_eq!(header.member().unwrap(), "EnableChargeThreshold");
        assert_eq!(message.body().signature().to_string(), "b");
        assert!(message.body().deserialize::<bool>().unwrap());
    }
}
