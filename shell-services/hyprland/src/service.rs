//! One socket2 subscription, debounced socket1 queries, and a `watch` of the result.

use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use std::time::Duration;

use tokio::io::AsyncBufReadExt;
use tokio::sync::{broadcast, watch};
use tokio::task::JoinHandle;
use tokio::time::Instant;

use koompi_service::{Backoff, PollRate, Result, Service};

use crate::binds::parse_binds;
use crate::event::{refresh_for, Event, Refresh};
use crate::ipc::Ipc;
use crate::model::{Client, HyprlandState, Monitor, MonitorLayers, Workspace};
use crate::xkb::{keyboard_from_devices, parse_activelayout, LayoutIndex, BASE_LST};

/// `HyprlandData.qml:81`. Scaled by [`PollRate`], never used raw.
const DEBOUNCE_BASE: Duration = Duration::from_millis(30);
const EVENT_CAPACITY: usize = 256;

pub struct HyprlandService {
    ipc: Ipc,
    state_tx: watch::Sender<HyprlandState>,
    events_tx: broadcast::Sender<Event>,
    poll_rate: Arc<AtomicU32>,
    worker: JoinHandle<()>,
}

impl Service for HyprlandService {
    type State = HyprlandState;

    fn state(&self) -> HyprlandState {
        self.state_tx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<HyprlandState> {
        self.state_tx.subscribe()
    }
}

impl Drop for HyprlandService {
    fn drop(&mut self) {
        self.worker.abort();
    }
}

impl HyprlandService {
    /// Fails only when there is no compositor to talk to. A compositor that dies later is
    /// the worker's problem, not the caller's.
    pub async fn start(rate: PollRate) -> Result<Self> {
        Ok(Self::with_ipc(Ipc::from_env()?, rate))
    }

    /// For a caller that already knows which instance it wants, and for tests that stand
    /// up a socket pair of their own.
    pub fn with_ipc(ipc: Ipc, rate: PollRate) -> Self {
        let state_tx = watch::Sender::new(HyprlandState::default());
        let events_tx = broadcast::Sender::new(EVENT_CAPACITY);
        let poll_rate = Arc::new(AtomicU32::new(rate.factor()));

        let worker = Worker {
            ipc: ipc.clone(),
            state_tx: state_tx.clone(),
            events_tx: events_tx.clone(),
            poll_rate: poll_rate.clone(),
        };

        Self {
            ipc,
            state_tx,
            events_tx,
            poll_rate,
            worker: tokio::spawn(worker.run()),
        }
    }

    /// Raw compositor events in arrival order, for a consumer that needs the event itself
    /// rather than the state it produced.
    pub fn events(&self) -> broadcast::Receiver<Event> {
        self.events_tx.subscribe()
    }

    pub fn ipc(&self) -> &Ipc {
        &self.ipc
    }

    pub fn poll_rate(&self) -> PollRate {
        PollRate::new(self.poll_rate.load(Ordering::Relaxed))
    }

    pub fn set_poll_rate(&self, rate: PollRate) {
        self.poll_rate.store(rate.factor(), Ordering::Relaxed);
    }

    pub fn debounce(&self) -> Duration {
        self.poll_rate().interval(DEBOUNCE_BASE)
    }

    /// Resolves once the first full query has landed.
    pub async fn ready(&self) -> HyprlandState {
        let mut rx = self.state_tx.subscribe();
        let ready = rx.wait_for(|state| state.connected).await;
        match ready {
            Ok(state) => state.clone(),
            Err(_) => self.state(),
        }
    }
}

#[derive(Clone)]
struct Worker {
    ipc: Ipc,
    state_tx: watch::Sender<HyprlandState>,
    events_tx: broadcast::Sender<Event>,
    poll_rate: Arc<AtomicU32>,
}

impl Worker {
    async fn run(self) {
        let mut backoff = Backoff::default();
        let mut layouts = LayoutIndex::load(BASE_LST).await.unwrap_or_default();

        loop {
            let _ = self.session(&mut layouts, &mut backoff).await;
            self.state_tx.send_if_modified(|state| {
                let was = state.connected;
                state.connected = false;
                was
            });
            backoff.wait().await;
        }
    }

    async fn session(&self, layouts: &mut LayoutIndex, backoff: &mut Backoff) -> Result<()> {
        let stream = self.ipc.events().await?;
        self.refresh(Refresh::ALL, layouts).await?;
        self.state_tx.send_if_modified(|state| {
            let was = state.connected;
            state.connected = true;
            !was
        });
        backoff.reset();

        let mut lines = tokio::io::BufReader::new(stream).lines();
        let mut pending = Refresh::NONE;
        let mut deadline: Option<Instant> = None;

        loop {
            tokio::select! {
                line = lines.next_line() => {
                    let Some(line) = line? else { return Ok(()) };
                    let Some(event) = Event::parse(line.trim_end()) else { continue };

                    self.apply_payload(&event, layouts);
                    let _ = self.events_tx.send(event.clone());

                    let refresh = refresh_for(&event.name);
                    if !refresh.is_empty() {
                        pending.merge(refresh);
                        deadline = Some(Instant::now() + self.debounce());
                    }
                }
                () = sleep_until(deadline) => {
                    deadline = None;
                    let refresh = std::mem::replace(&mut pending, Refresh::NONE);
                    self.refresh(refresh, layouts).await?;
                }
            }
        }
    }

    fn debounce(&self) -> Duration {
        PollRate::new(self.poll_rate.load(Ordering::Relaxed)).interval(DEBOUNCE_BASE)
    }

    /// Events that carry their own answer, so no query follows them.
    fn apply_payload(&self, event: &Event, layouts: &LayoutIndex) {
        match event.name.as_str() {
            "activelayout" => {
                let Some((keyboard, description)) = parse_activelayout(&event.data) else {
                    return;
                };
                let code = layouts.code_for(description).unwrap_or_default().to_string();
                self.state_tx.send_if_modified(|state| {
                    if !state.keyboard.name.is_empty() && state.keyboard.name != keyboard {
                        return false;
                    }
                    if state.keyboard.active_name == description {
                        return false;
                    }
                    state.keyboard.active_name = description.to_string();
                    state.keyboard.active_code = code;
                    true
                });
            }
            "submap" => {
                self.state_tx.send_if_modified(|state| {
                    if state.submap == event.data {
                        return false;
                    }
                    state.submap = event.data.clone();
                    true
                });
            }
            _ => {}
        }
    }

    async fn refresh(&self, refresh: Refresh, layouts: &mut LayoutIndex) -> Result<()> {
        if refresh.is_empty() {
            return Ok(());
        }

        let windows: Option<Vec<Client>> = match refresh.clients {
            true => Some(self.ipc.request_json("j/clients").await?),
            false => None,
        };
        let workspaces: Option<Vec<Workspace>> = match refresh.workspaces {
            true => Some(self.ipc.request_json("j/workspaces").await?),
            false => None,
        };
        let active_workspace = match refresh.workspaces {
            true => Some(self.query_active("j/activeworkspace").await?),
            false => None,
        };
        let active_window = match refresh.active_window {
            true => Some(self.query_active("j/activewindow").await?),
            false => None,
        };
        let monitors: Option<Vec<Monitor>> = match refresh.monitors {
            true => Some(self.ipc.request_json("j/monitors").await?),
            false => None,
        };
        let layers: Option<std::collections::BTreeMap<String, MonitorLayers>> =
            match refresh.layers {
                true => Some(self.ipc.request_json("j/layers").await?),
                false => None,
            };
        // Plain text, not j/binds: see the note on parse_binds.
        let keybinds = match refresh.binds {
            true => Some(parse_binds(&self.ipc.request("binds").await?)),
            false => None,
        };
        let keyboard = match refresh.devices {
            true => {
                *layouts = LayoutIndex::load(BASE_LST).await.unwrap_or_default();
                let mut keyboard = keyboard_from_devices(&self.ipc.request("j/devices").await?)?;
                keyboard.active_code = layouts
                    .code_for(&keyboard.active_name)
                    .unwrap_or_default()
                    .to_string();
                Some(keyboard)
            }
            false => None,
        };

        self.state_tx.send_if_modified(|state| {
            let mut changed = false;
            changed |= replace(&mut state.windows, windows);
            changed |= replace(&mut state.workspaces, workspaces);
            changed |= replace(&mut state.active_workspace, active_workspace);
            changed |= replace(&mut state.active_window, active_window);
            changed |= replace(&mut state.monitors, monitors);
            changed |= replace(&mut state.layers, layers);
            changed |= replace(&mut state.keybinds, keybinds);
            changed |= replace(&mut state.keyboard, keyboard);
            changed
        });

        Ok(())
    }

    /// `j/activewindow` answers `{}` when nothing is focused, and the same holds for a
    /// workspace query on a monitor that has none.
    async fn query_active<T: serde::de::DeserializeOwned>(&self, command: &str) -> Result<Option<T>> {
        let reply = self.ipc.request(command).await?;
        let reply = reply.trim();
        if reply.is_empty() || reply == "{}" {
            return Ok(None);
        }
        serde_json::from_str(reply)
            .map(Some)
            .map_err(|e| koompi_service::Error::Protocol(format!("{command}: {e}")))
    }
}

fn replace<T: PartialEq>(current: &mut T, next: Option<T>) -> bool {
    match next {
        Some(next) if *current != next => {
            *current = next;
            true
        }
        _ => false,
    }
}

async fn sleep_until(deadline: Option<Instant>) {
    match deadline {
        Some(deadline) => tokio::time::sleep_until(deadline).await,
        None => std::future::pending().await,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_debounce_is_the_qml_interval_scaled_by_the_power_saving_multiplier() {
        let rate = Arc::new(AtomicU32::new(PollRate::NORMAL.factor()));
        let worker = Worker {
            ipc: Ipc::new("/nonexistent"),
            state_tx: watch::Sender::new(HyprlandState::default()),
            events_tx: broadcast::Sender::new(4),
            poll_rate: rate.clone(),
        };

        assert_eq!(worker.debounce(), Duration::from_millis(30));
        rate.store(PollRate::SAVING.factor(), Ordering::Relaxed);
        assert_eq!(worker.debounce(), Duration::from_millis(60));
    }

    #[test]
    fn only_a_different_value_marks_the_state_changed() {
        let mut windows = vec![Client::default()];
        assert!(!replace(&mut windows, None));
        assert!(!replace(&mut windows, Some(vec![Client::default()])));
        assert!(replace(&mut windows, Some(Vec::new())));
        assert!(windows.is_empty());
    }

    #[tokio::test]
    async fn a_payload_event_updates_state_without_touching_the_socket() {
        let worker = Worker {
            ipc: Ipc::new("/nonexistent"),
            state_tx: watch::Sender::new(HyprlandState::default()),
            events_tx: broadcast::Sender::new(4),
            poll_rate: Arc::new(AtomicU32::new(1)),
        };
        let layouts = LayoutIndex::parse(include_str!("../tests/fixtures/base.lst"));

        worker.apply_payload(
            &Event::parse("activelayout>>at-translated-set-2-keyboard,Khmer (Cambodia)").unwrap(),
            &layouts,
        );
        worker.apply_payload(&Event::parse("submap>>virtual-machine").unwrap(), &layouts);

        let state = worker.state_tx.borrow();
        assert_eq!(state.keyboard.active_name, "Khmer (Cambodia)");
        assert_eq!(state.keyboard.active_code, "kh");
        assert_eq!(state.submap, "virtual-machine");
    }

    #[tokio::test]
    async fn no_compositor_in_the_environment_is_unavailable() {
        use koompi_service::Error;

        let dir = crate::ipc::resolve_instance_dir(None, None);
        assert!(matches!(dir, Err(Error::Unavailable(_))));
    }
}
