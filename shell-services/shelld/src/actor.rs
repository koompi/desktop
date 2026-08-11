//! One task per subscribed service, owning its whole lifecycle: connect, retry, coalesce,
//! and answer commands. The shape is identical for every service, so it lives here once
//! and each service supplies only what differs.

use std::future::Future;
use std::sync::Arc;
use std::time::Duration;

use koompi_service::{Backoff, Error, PollRate};
use serde_json::Value;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::Instant;

use crate::out::Out;
use crate::proto::{self, ErrorCode, Failure, Outcome};

pub trait Managed: Sized + Send + Sync + 'static {
    type State: Clone + Send + Sync + 'static;
    type Cmd: Send + 'static;

    const NAME: &'static str;

    fn connect(rate: PollRate) -> impl Future<Output = koompi_service::Result<Self>> + Send;

    fn watch(&self) -> watch::Receiver<Self::State>;

    fn encode(state: &Self::State) -> Value;

    /// False means the backing daemon went away while we were holding it, which is an
    /// outage to announce rather than a state to publish.
    fn healthy(_state: &Self::State) -> bool {
        true
    }

    fn set_poll_rate(&self, _rate: PollRate) {}

    fn apply(self: Arc<Self>, cmd: Self::Cmd) -> impl Future<Output = Outcome> + Send;
}

pub enum Job<C> {
    GetState { id: Option<i64> },
    /// A snapshot for a `subscribe` that named a service already running. It signals
    /// when the state is on the wire, so the subscribe's reply can still land behind it.
    Resend(oneshot::Sender<()>),
    SetPollRate(PollRate),
    Apply { id: Option<i64>, cmd: C },
}

pub type Jobs<M> = mpsc::Sender<Job<<M as Managed>::Cmd>>;

/// Why an inner loop gave up: the subscription was torn down, or the service was lost and
/// should be reconnected.
enum Exit {
    Shutdown,
    Lost,
}

/// The receiver fires once this service has put its first `state` or `unavailable` on the
/// wire, which is what lets `subscribe` reply after them rather than before.
pub fn spawn<M: Managed>(
    out: Out,
    rate: PollRate,
    debounce: Duration,
) -> (Jobs<M>, oneshot::Receiver<()>) {
    let (tx, rx) = mpsc::channel(32);
    let (ready_tx, ready_rx) = oneshot::channel();
    tokio::spawn(run::<M>(rx, out, rate, debounce, ready_tx));
    (tx, ready_rx)
}

async fn run<M: Managed>(
    mut jobs: mpsc::Receiver<Job<M::Cmd>>,
    out: Out,
    mut rate: PollRate,
    debounce: Duration,
    ready: oneshot::Sender<()>,
) {
    let mut backoff = Backoff::default();
    let mut serial = 0u64;
    let mut announced = false;
    let mut ready = Some(ready);

    loop {
        let service = match M::connect(rate).await {
            Ok(service) => Arc::new(service),
            Err(error) => {
                if !announced {
                    announced = true;
                    out.send(proto::unavailable(M::NAME, reason(&error), error.to_string()));
                    if let Some(ready) = ready.take() {
                        let _ = ready.send(());
                    }
                }
                match idle::<M>(&mut jobs, &out, &mut rate, backoff.next_delay()).await {
                    Exit::Shutdown => return,
                    Exit::Lost => continue,
                }
            }
        };

        backoff.reset();
        serial += 1;
        out.send(proto::state(
            M::NAME,
            serial,
            M::encode(&service.watch().borrow()),
        ));
        if let Some(ready) = ready.take() {
            let _ = ready.send(());
        }

        match serve(&service, &mut jobs, &out, &mut serial, debounce).await {
            Exit::Shutdown => return,
            Exit::Lost => {
                announced = true;
                out.send(proto::unavailable(
                    M::NAME,
                    "disconnected",
                    format!("{} stopped answering", M::NAME),
                ));
            }
        }
    }
}

/// Down and waiting to retry. Commands are still answered, because a consumer that fires
/// one into a service it cannot see deserves an error rather than silence.
async fn idle<M: Managed>(
    jobs: &mut mpsc::Receiver<Job<M::Cmd>>,
    out: &Out,
    rate: &mut PollRate,
    delay: Duration,
) -> Exit {
    let deadline = Instant::now() + delay;
    loop {
        tokio::select! {
            _ = tokio::time::sleep_until(deadline) => return Exit::Lost,
            job = jobs.recv() => match job {
                None => return Exit::Shutdown,
                Some(Job::SetPollRate(new_rate)) => *rate = new_rate,
                // the outage was announced when it started; there is no state to resend
                Some(Job::Resend(done)) => { let _ = done.send(()); }
                Some(Job::GetState { id }) | Some(Job::Apply { id, .. }) => out.send(proto::reply(
                    id,
                    Err(Failure::new(ErrorCode::Unavailable, M::NAME)),
                )),
            },
        }
    }
}

async fn serve<M: Managed>(
    service: &Arc<M>,
    jobs: &mut mpsc::Receiver<Job<M::Cmd>>,
    out: &Out,
    serial: &mut u64,
    debounce: Duration,
) -> Exit {
    let mut rx = service.watch();
    let mut due: Option<Instant> = None;

    loop {
        tokio::select! {
            // while a snapshot is pending the change branch stays off, so everything that
            // lands inside the window collapses into the one borrow_and_update below
            changed = rx.changed(), if due.is_none() => {
                if changed.is_err() {
                    return Exit::Lost;
                }
                due = Some(Instant::now() + debounce);
            }
            _ = sleep_until(due), if due.is_some() => {
                due = None;
                let state = rx.borrow_and_update().clone();
                if !M::healthy(&state) {
                    return Exit::Lost;
                }
                *serial += 1;
                out.send(proto::state(M::NAME, *serial, M::encode(&state)));
            }
            job = jobs.recv() => match job {
                None => return Exit::Shutdown,
                Some(Job::SetPollRate(rate)) => service.set_poll_rate(rate),
                Some(Job::GetState { id }) => {
                    *serial += 1;
                    out.send(proto::state(M::NAME, *serial, M::encode(&rx.borrow())));
                    out.send(proto::reply(id, Ok(())));
                }
                Some(Job::Resend(done)) => {
                    *serial += 1;
                    out.send(proto::state(M::NAME, *serial, M::encode(&rx.borrow())));
                    let _ = done.send(());
                }
                Some(Job::Apply { id, cmd }) => {
                    // off the loop, so a d-bus round trip does not hold up the snapshots
                    // the same round trip is about to produce
                    let service = Arc::clone(service);
                    let out = out.clone();
                    tokio::spawn(async move {
                        out.send(proto::reply(id, service.apply(cmd).await));
                    });
                }
            },
        }
    }
}

async fn sleep_until(due: Option<Instant>) {
    match due {
        Some(deadline) => tokio::time::sleep_until(deadline).await,
        None => std::future::pending().await,
    }
}

fn reason(error: &Error) -> &'static str {
    match error {
        Error::Unavailable(_) => "no_daemon",
        Error::Bus(_) => "no_bus",
        _ => "refused",
    }
}
