//! One `audiod` child, restarted through [`Backoff`], and a `watch` of what it reports.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, oneshot, watch};
use tokio::task::JoinHandle;

use koompi_service::{Backoff, Error, PollRate, Result, Service};

use crate::model::{AudioState, DaemonStatus};
use crate::proto::{Command, Message, MAX_VOLUME};

/// `GlobalMenuService.qml:105-109` restarts the global menu daemon after 3000 ms. Scaled
/// by [`PollRate`], never used raw.
const RESTART_BASE: Duration = Duration::from_millis(3000);
const RESTART_CAP: Duration = Duration::from_secs(30);
const COMMAND_QUEUE: usize = 32;

/// Overrides the binary. Named for the variable `audiod/tests/test_audiod.py` already
/// uses, so one export points the suite and this crate at the same build.
pub const BINARY_ENV: &str = "AUDIOD";

const IN_TREE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../audiod/zig-out/bin/audiod");

/// The resolution `GlobalMenuService.qml:14-21` performs for its own daemon: an override,
/// then what a package installed, then the build in this tree.
pub fn resolve_binary() -> Result<PathBuf> {
    // an override that does not exist is unavailable, not a reason to fall back to
    // whatever else happens to be installed
    if let Some(override_path) = std::env::var_os(BINARY_ENV).filter(|path| !path.is_empty()) {
        return present(PathBuf::from(override_path));
    }

    let mut installed = std::env::var_os("HOME")
        .map(|home| Path::new(&home).join(".local/bin/audiod"))
        .into_iter()
        .chain([PathBuf::from("/usr/bin/audiod"), PathBuf::from(IN_TREE)]);

    installed
        .find(|path| path.is_file())
        .ok_or_else(|| Error::Unavailable("audiod".into()))
}

fn present(path: PathBuf) -> Result<PathBuf> {
    match path.is_file() {
        true => Ok(path),
        false => Err(Error::Unavailable(format!("audiod ({})", path.display()))),
    }
}

type Pending = (Command, oneshot::Sender<Result<()>>);
type Awaiting = HashMap<u64, oneshot::Sender<Result<()>>>;

pub struct AudioService {
    binary: PathBuf,
    state_tx: watch::Sender<AudioState>,
    status_tx: watch::Sender<DaemonStatus>,
    commands_tx: mpsc::Sender<Pending>,
    poll_rate: Arc<AtomicU32>,
    next_id: AtomicU64,
    worker: JoinHandle<()>,
}

impl Service for AudioService {
    type State = AudioState;

    fn state(&self) -> AudioState {
        self.state_tx.borrow().clone()
    }

    fn subscribe(&self) -> watch::Receiver<AudioState> {
        self.state_tx.subscribe()
    }
}

impl Drop for AudioService {
    fn drop(&mut self) {
        self.worker.abort();
    }
}

impl AudioService {
    /// Fails only when there is no daemon binary to run. A daemon that dies later, or that
    /// cannot reach PipeWire, is the worker's problem and shows up in [`Self::status`].
    pub fn start(rate: PollRate) -> Result<Self> {
        Ok(Self::with_binary(resolve_binary()?, rate))
    }

    pub fn with_binary(binary: PathBuf, rate: PollRate) -> Self {
        let state_tx = watch::Sender::new(AudioState::default());
        let status_tx = watch::Sender::new(DaemonStatus::default());
        let (commands_tx, commands_rx) = mpsc::channel(COMMAND_QUEUE);
        let poll_rate = Arc::new(AtomicU32::new(rate.factor()));

        let worker = Worker {
            binary: binary.clone(),
            state_tx: state_tx.clone(),
            status_tx: status_tx.clone(),
            poll_rate: poll_rate.clone(),
        };

        Self {
            binary,
            state_tx,
            status_tx,
            commands_tx,
            poll_rate,
            next_id: AtomicU64::new(1),
            worker: tokio::spawn(worker.run(commands_rx)),
        }
    }

    pub fn binary(&self) -> &Path {
        &self.binary
    }

    pub fn status(&self) -> DaemonStatus {
        self.status_tx.borrow().clone()
    }

    pub fn subscribe_status(&self) -> watch::Receiver<DaemonStatus> {
        self.status_tx.subscribe()
    }

    pub fn poll_rate(&self) -> PollRate {
        PollRate::new(self.poll_rate.load(Ordering::Relaxed))
    }

    pub fn set_poll_rate(&self, rate: PollRate) {
        self.poll_rate.store(rate.factor(), Ordering::Relaxed);
    }

    /// Resolves once the first snapshot has landed, or fails as soon as the daemon says
    /// PipeWire is not there. A seat with no sound server is a working seat.
    pub async fn ready(&self) -> Result<AudioState> {
        let mut state = self.state_tx.subscribe();
        let mut status = self.status_tx.subscribe();
        loop {
            if let Some(unavailable) = status.borrow_and_update().unavailable.clone() {
                return Err(Error::Unavailable(format!(
                    "pipewire ({}: {})",
                    unavailable.reason, unavailable.message
                )));
            }
            {
                let current = state.borrow_and_update();
                if current.ready {
                    return Ok(current.clone());
                }
            }
            tokio::select! {
                changed = state.changed() => changed.map_err(|_| worker_gone())?,
                changed = status.changed() => changed.map_err(|_| worker_gone())?,
            }
        }
    }

    pub async fn ping(&self) -> Result<()> {
        self.request(Command::Ping { id: self.id() }).await
    }

    /// Asks for a fresh snapshot. The state it produces arrives through the `watch` before
    /// this returns, since the protocol emits the `state` ahead of the reply.
    pub async fn refresh(&self) -> Result<()> {
        self.request(Command::GetState { id: self.id() }).await
    }

    /// `ok` means PipeWire accepted the parameter. The value that landed arrives as a
    /// state change, so a caller that needs to confirm it watches rather than trusts this.
    pub async fn set_volume(&self, node: u32, volume: f64) -> Result<()> {
        if !(0.0..=MAX_VOLUME).contains(&volume) {
            return Err(Error::Protocol(format!(
                "volume {volume} is outside [0, {MAX_VOLUME}]"
            )));
        }
        self.request(Command::SetVolume {
            id: self.id(),
            node,
            volume,
        })
        .await
    }

    pub async fn set_mute(&self, node: u32, mute: bool) -> Result<()> {
        self.request(Command::SetMute {
            id: self.id(),
            node,
            mute,
        })
        .await
    }

    pub async fn set_default_sink(&self, name: &str) -> Result<()> {
        self.request(Command::SetDefaultSink {
            id: self.id(),
            name: name.to_string(),
        })
        .await
    }

    pub async fn set_default_source(&self, name: &str) -> Result<()> {
        self.request(Command::SetDefaultSource {
            id: self.id(),
            name: name.to_string(),
        })
        .await
    }

    fn id(&self) -> u64 {
        self.next_id.fetch_add(1, Ordering::Relaxed)
    }

    async fn request(&self, command: Command) -> Result<()> {
        let (tx, rx) = oneshot::channel();
        self.commands_tx
            .send((command, tx))
            .await
            .map_err(|_| worker_gone())?;
        rx.await.map_err(|_| worker_gone())?
    }
}

fn worker_gone() -> Error {
    Error::Unavailable("audiod".into())
}

struct Worker {
    binary: PathBuf,
    state_tx: watch::Sender<AudioState>,
    status_tx: watch::Sender<DaemonStatus>,
    poll_rate: Arc<AtomicU32>,
}

impl Worker {
    async fn run(self, mut commands: mpsc::Receiver<Pending>) {
        let mut base = self.restart_base();
        let mut backoff = Backoff::new(base, RESTART_CAP);

        loop {
            let _ = self.session(&mut commands).await;
            let reached_ready = self.state_tx.borrow().ready;
            self.mark_stopped();

            if reached_ready {
                backoff.reset();
            }
            let current = self.restart_base();
            if current != base {
                base = current;
                backoff = Backoff::new(base, RESTART_CAP);
            }
            self.reject_while_down(backoff.next_delay(), &mut commands)
                .await;
        }
    }

    /// A command issued while the daemon is down fails now rather than sitting in the
    /// queue until the restart lands and answering for a process the caller never saw.
    async fn reject_while_down(&self, delay: Duration, commands: &mut mpsc::Receiver<Pending>) {
        let sleep = tokio::time::sleep(delay);
        tokio::pin!(sleep);
        loop {
            tokio::select! {
                () = &mut sleep => return,
                request = commands.recv() => match request {
                    Some((_, reply)) => { let _ = reply.send(Err(worker_gone())); }
                    None => return sleep.await,
                },
            }
        }
    }

    fn restart_base(&self) -> Duration {
        PollRate::new(self.poll_rate.load(Ordering::Relaxed)).interval(RESTART_BASE)
    }

    async fn session(&self, commands: &mut mpsc::Receiver<Pending>) -> Result<()> {
        let mut child = tokio::process::Command::new(&self.binary)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(|error| match error.kind() {
                std::io::ErrorKind::NotFound => {
                    Error::Unavailable(format!("audiod ({})", self.binary.display()))
                }
                _ => Error::Io(error),
            })?;

        let (Some(mut stdin), Some(stdout)) = (child.stdin.take(), child.stdout.take()) else {
            return Err(Error::Protocol("audiod stdio was not piped".into()));
        };
        let mut lines = BufReader::new(stdout).lines();
        let mut pending = Awaiting::new();

        self.status_tx.send_modify(|status| {
            status.running = true;
            status.unavailable = None;
        });

        let outcome = loop {
            tokio::select! {
                line = lines.next_line() => match line {
                    Ok(Some(line)) => self.handle(&line, &mut pending),
                    Ok(None) => break Ok(()),
                    Err(error) => break Err(error.into()),
                },
                request = commands.recv() => {
                    let Some((command, reply)) = request else { break Ok(()) };
                    match stdin.write_all(command.line().as_bytes()).await {
                        Ok(()) => { pending.insert(command.id(), reply); }
                        Err(error) => {
                            let _ = reply.send(Err(Error::Io(error)));
                            break Ok(());
                        }
                    }
                }
            }
        };

        for (_, reply) in pending {
            let _ = reply.send(Err(worker_gone()));
        }
        outcome
    }

    /// A line that does not parse is skipped rather than fatal: the protocol requires a
    /// reader to tolerate what it does not understand.
    fn handle(&self, line: &str, pending: &mut Awaiting) {
        let Ok(message) = Message::parse(line.trim()) else {
            return;
        };

        match &message {
            Message::Hello(hello) => self.status_tx.send_modify(|status| {
                status.hello = Some(hello.clone());
            }),
            Message::Reply(reply) => {
                if let Some(sender) = reply.id.and_then(|id| pending.remove(&id)) {
                    let _ = sender.send(reply.outcome());
                }
            }
            Message::Error(error) => self.status_tx.send_modify(|status| {
                status.last_error = Some(error.clone());
            }),
            Message::Unavailable(unavailable) => self.status_tx.send_modify(|status| {
                status.unavailable = Some(unavailable.clone());
            }),
            _ => {}
        }

        self.state_tx.send_if_modified(|state| state.apply(&message));
    }

    fn mark_stopped(&self) {
        self.state_tx.send_if_modified(|state| {
            let was = state.ready;
            state.ready = false;
            was
        });
        self.status_tx.send_modify(|status| status.running = false);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn worker(rate: PollRate) -> Worker {
        Worker {
            binary: PathBuf::from("/nonexistent/audiod"),
            state_tx: watch::Sender::new(AudioState::default()),
            status_tx: watch::Sender::new(DaemonStatus::default()),
            poll_rate: Arc::new(AtomicU32::new(rate.factor())),
        }
    }

    #[test]
    fn the_restart_interval_is_the_qml_one_scaled_by_the_power_saving_multiplier() {
        assert_eq!(
            worker(PollRate::NORMAL).restart_base(),
            Duration::from_millis(3000)
        );
        assert_eq!(
            worker(PollRate::SAVING).restart_base(),
            Duration::from_millis(6000)
        );
    }

    /// One test, because the environment it edits is process wide and the cases would
    /// otherwise race each other across the test threads.
    #[test]
    fn binary_resolution_prefers_the_override_and_never_falls_back_past_it() {
        temp_env(BINARY_ENV, Some("/nonexistent/audiod"), || {
            let error = resolve_binary().unwrap_err();
            assert!(matches!(error, Error::Unavailable(_)), "{error}");
            assert!(error.to_string().contains("/nonexistent/audiod"));
        });

        if Path::new(IN_TREE).is_file() {
            temp_env(BINARY_ENV, Some(IN_TREE), || {
                assert_eq!(resolve_binary().unwrap(), PathBuf::from(IN_TREE));
            });
        }

        temp_env(BINARY_ENV, None, || match resolve_binary() {
            Ok(path) => assert!(path.is_file(), "{}", path.display()),
            Err(error) => assert!(matches!(error, Error::Unavailable(_)), "{error}"),
        });
    }

    #[tokio::test]
    async fn a_binary_that_cannot_be_spawned_leaves_the_service_unready_without_panicking() {
        let service = AudioService::with_binary(PathBuf::from("/nonexistent/audiod"), PollRate::NORMAL);
        let waited = tokio::time::timeout(Duration::from_millis(200), service.ready()).await;

        assert!(waited.is_err(), "ready resolved against a missing binary");
        assert!(!service.state().ready);
    }

    #[tokio::test]
    async fn a_command_with_no_daemon_behind_it_fails_as_unavailable() {
        let service = AudioService::with_binary(PathBuf::from("/nonexistent/audiod"), PollRate::NORMAL);
        let error = service.ping().await.unwrap_err();
        assert!(matches!(error, Error::Unavailable(_)), "{error}");
    }

    #[tokio::test]
    async fn a_volume_outside_the_documented_range_never_reaches_the_daemon() {
        let service = AudioService::with_binary(PathBuf::from("/nonexistent/audiod"), PollRate::NORMAL);
        for volume in [-0.1, 2.1, f64::NAN] {
            let error = service.set_volume(85, volume).await.unwrap_err();
            assert!(matches!(error, Error::Protocol(_)), "{volume}: {error}");
        }
    }

    /// `std::env::set_var` is process wide, so the environment is put back before the
    /// assertion can unwind past it.
    fn temp_env(key: &str, value: Option<&str>, body: impl FnOnce()) {
        let previous = std::env::var_os(key);
        match value {
            Some(value) => std::env::set_var(key, value),
            None => std::env::remove_var(key),
        }
        let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(body));
        match previous {
            Some(previous) => std::env::set_var(key, previous),
            None => std::env::remove_var(key),
        }
        if let Err(payload) = outcome {
            std::panic::resume_unwind(payload);
        }
    }
}
