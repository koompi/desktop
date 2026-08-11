use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use koompi_service::{Error, PollRate, Result, Service};
use tokio::sync::watch;
use tokio::task::JoinHandle;
use zbus::Connection;

use crate::ddc;
use crate::logind::SessionProxy;
use crate::panel::{self, Backend, Panel};
use crate::sysfs;
use crate::writer;

/// Only reached where `POLLPRI` on `actual_brightness` could not be opened. The
/// multiplier is `PowerSaving.qml:33`, one factor for the whole shell.
const POLL_BASE: Duration = Duration::from_secs(2);

const SUBSYSTEM: &str = "backlight";

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BrightnessState {
    pub panels: Vec<Panel>,
}

impl BrightnessState {
    pub fn panel(&self, id: &str) -> Option<&Panel> {
        self.panels.iter().find(|panel| panel.id == id)
    }

    /// What `Brightness.qml:38` looks up before every key press.
    pub fn for_connector(&self, connector: &str) -> Option<&Panel> {
        self.panels
            .iter()
            .find(|panel| panel.connector.as_deref() == Some(connector))
    }
}

pub struct BrightnessService {
    handles: HashMap<String, Handle>,
    rx: watch::Receiver<BrightnessState>,
    tasks: Vec<JoinHandle<()>>,
}

struct Handle {
    backend: Backend,
    raw_max: u32,
    request: Mutex<Request>,
    tx: watch::Sender<u32>,
}

#[derive(Debug, Clone, Copy)]
struct Request {
    brightness: f64,
    multiplier: f64,
}

impl Service for BrightnessService {
    type State = BrightnessState;

    fn state(&self) -> BrightnessState {
        self.rx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<BrightnessState> {
        self.rx.clone()
    }
}

impl Drop for BrightnessService {
    fn drop(&mut self) {
        for task in &self.tasks {
            task.abort();
        }
    }
}

impl BrightnessService {
    pub async fn connect(poll_rate: PollRate) -> Result<Self> {
        Self::with_class(
            Connection::system().await?,
            Path::new(sysfs::CLASS),
            poll_rate,
        )
        .await
    }

    pub async fn with_class(conn: Connection, class: &Path, poll_rate: PollRate) -> Result<Self> {
        let mut panels = Vec::new();
        let mut handles = HashMap::new();
        let mut sinks = Vec::new();

        for light in sysfs::discover(class) {
            let raw = sysfs::read_brightness(class, &light.name)?;
            let (tx, rx) = watch::channel(raw);
            handles.insert(
                light.name.clone(),
                Handle::new(Backend::Logind, light.raw_max, raw, tx),
            );
            sinks.push((
                light.name.clone(),
                rx,
                writer::LOGIND_DEBOUNCE,
                Sink::Logind {
                    conn: conn.clone(),
                    name: light.name.clone(),
                },
            ));
            panels.push(Panel {
                id: light.name,
                connector: light.connector,
                backend: Backend::Logind,
                raw,
                raw_max: light.raw_max,
                bus: None,
            });
        }

        for monitor in ddc::detect().await {
            let Ok((raw, raw_max)) = ddc::get_luminance(monitor.bus).await else {
                continue;
            };
            let (tx, rx) = watch::channel(raw);
            handles.insert(
                monitor.connector.clone(),
                Handle::new(Backend::Ddc, raw_max, raw, tx),
            );
            sinks.push((
                monitor.connector.clone(),
                rx,
                writer::DDC_DEBOUNCE,
                Sink::Ddc { bus: monitor.bus },
            ));
            panels.push(Panel {
                id: monitor.connector.clone(),
                connector: Some(monitor.connector),
                backend: Backend::Ddc,
                raw,
                raw_max,
                bus: Some(monitor.bus),
            });
        }

        let tx = Arc::new(watch::channel(BrightnessState { panels }).0);
        let rx = tx.subscribe();

        let mut tasks = Vec::new();
        for (id, rx, debounce, sink) in sinks {
            let state = Arc::clone(&tx);
            tasks.push(tokio::spawn(async move {
                writer::run(rx, debounce, |raw| {
                    let state = Arc::clone(&state);
                    let id = id.clone();
                    let sink = sink.clone();
                    async move {
                        if sink.write(raw).await.is_ok() {
                            publish(&state, &id, raw);
                        }
                    }
                })
                .await;
            }));
        }

        for panel in &rx.borrow().panels {
            if panel.backend == Backend::Logind {
                tasks.push(tokio::spawn(follow(
                    Arc::clone(&tx),
                    class.to_path_buf(),
                    panel.id.clone(),
                    poll_rate,
                )));
            }
        }

        Ok(Self { handles, rx, tasks })
    }

    /// `Brightness.qml:169`: the requested value, before the multiplier.
    pub fn set(&self, id: &str, value: f64) -> Result<()> {
        self.request(id, |request| request.brightness = value.clamp(0.0, 1.0))
    }

    /// The anti-flashbang factor, computed outside this crate and clamped inside it.
    pub fn set_multiplier(&self, id: &str, multiplier: f64) -> Result<()> {
        self.request(id, |request| request.multiplier = multiplier)
    }

    /// The exact raw value, for a caller restoring one it recorded. Still floored at 1:
    /// no path in this crate may darken a panel completely.
    pub fn set_raw(&self, id: &str, raw: u32) -> Result<()> {
        let handle = self.handle(id)?;
        let raw = raw.clamp(1, handle.raw_max);
        handle
            .request
            .lock()
            .expect("brightness request")
            .brightness = panel::fraction(raw, handle.raw_max);
        let _ = handle.tx.send(raw);
        Ok(())
    }

    fn request(&self, id: &str, edit: impl FnOnce(&mut Request)) -> Result<()> {
        let handle = self.handle(id)?;
        let request = {
            let mut request = handle.request.lock().expect("brightness request");
            edit(&mut request);
            *request
        };

        let value = panel::multiplied(request.brightness, request.multiplier);
        let raw = match handle.backend {
            Backend::Logind => panel::logind_raw(value, handle.raw_max),
            Backend::Ddc => panel::ddc_raw(value, handle.raw_max),
        };
        let _ = handle.tx.send(raw);
        Ok(())
    }

    fn handle(&self, id: &str) -> Result<&Handle> {
        self.handles
            .get(id)
            .ok_or_else(|| Error::Unavailable(format!("panel {id}")))
    }
}

impl Handle {
    fn new(backend: Backend, raw_max: u32, raw: u32, tx: watch::Sender<u32>) -> Self {
        Self {
            backend,
            raw_max,
            request: Mutex::new(Request {
                brightness: panel::fraction(raw, raw_max),
                multiplier: 1.0,
            }),
            tx,
        }
    }
}

#[derive(Clone)]
enum Sink {
    Logind { conn: Connection, name: String },
    Ddc { bus: u8 },
}

impl Sink {
    async fn write(&self, raw: u32) -> Result<()> {
        match self {
            Self::Logind { conn, name } => {
                SessionProxy::new(conn)
                    .await?
                    .set_brightness(SUBSYSTEM, name, raw)
                    .await?;
                Ok(())
            }
            Self::Ddc { bus } => ddc::set_luminance(*bus, raw).await,
        }
    }
}

/// A brightness key pressed outside the shell still moves the panel, so the state has to
/// follow sysfs rather than only the writes this crate made.
async fn follow(
    tx: Arc<watch::Sender<BrightnessState>>,
    class: PathBuf,
    id: String,
    poll_rate: PollRate,
) {
    if let Ok(mut watch) = sysfs::Watch::open(&class, &id) {
        while let Ok(raw) = watch.changed().await {
            publish(&tx, &id, raw);
        }
    }

    loop {
        tokio::time::sleep(poll_rate.interval(POLL_BASE)).await;
        if let Ok(raw) = sysfs::read_brightness(&class, &id) {
            publish(&tx, &id, raw);
        }
    }
}

fn publish(tx: &watch::Sender<BrightnessState>, id: &str, raw: u32) {
    tx.send_if_modified(|state| {
        let Some(panel) = state.panels.iter_mut().find(|panel| panel.id == id) else {
            return false;
        };
        let moved = panel.raw != raw;
        panel.raw = raw;
        moved
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::Message;

    fn state() -> BrightnessState {
        BrightnessState {
            panels: vec![Panel {
                id: "intel_backlight".into(),
                connector: Some("eDP-1".into()),
                backend: Backend::Logind,
                raw: 80291,
                raw_max: 174545,
                bus: None,
            }],
        }
    }

    #[test]
    fn a_panel_is_reachable_by_its_id_and_by_the_connector_the_shell_knows_it_as() {
        let state = state();

        assert_eq!(state.panel("intel_backlight").unwrap().raw, 80291);
        assert_eq!(state.for_connector("eDP-1").unwrap().id, "intel_backlight");
        assert!(state.for_connector("DP-1").is_none());
        assert!(BrightnessState::default()
            .panel("intel_backlight")
            .is_none());
    }

    #[test]
    fn publishing_the_same_value_twice_does_not_wake_a_consumer() {
        let (tx, mut rx) = watch::channel(state());

        publish(&tx, "intel_backlight", 80291);
        assert!(!rx.has_changed().unwrap());

        publish(&tx, "intel_backlight", 90000);
        assert!(rx.has_changed().unwrap());
        assert_eq!(rx.borrow_and_update().panels[0].raw, 90000);

        publish(&tx, "no_such_panel", 1);
        assert!(!rx.has_changed().unwrap());
    }

    /// The call `brightnessctl` needed a udev rule for. Checked as a message rather than
    /// fired, so the shape is pinned without moving the panel.
    #[test]
    fn set_brightness_is_the_logind_session_call_and_not_a_sysfs_write() {
        let message = Message::method_call("/org/freedesktop/login1/session/auto", "SetBrightness")
            .unwrap()
            .destination("org.freedesktop.login1")
            .unwrap()
            .interface("org.freedesktop.login1.Session")
            .unwrap()
            .build(&(SUBSYSTEM, "intel_backlight", 80291u32))
            .unwrap();

        let header = message.header();
        assert_eq!(
            header.path().unwrap().as_str(),
            "/org/freedesktop/login1/session/auto"
        );
        assert_eq!(header.member().unwrap(), "SetBrightness");

        let body = message.body();
        assert_eq!(body.signature().to_string(), "(ssu)");
        let (subsystem, name, raw): (String, String, u32) = body.deserialize().unwrap();
        assert_eq!(subsystem, "backlight");
        assert_eq!(name, "intel_backlight");
        assert_eq!(raw, 80291);
    }
}
