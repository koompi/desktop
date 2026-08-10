//! `koompi-shelld`, the one daemon the shell spawns. See `PROTOCOL.md`, which is the
//! contract; this file is only how it is met.

mod actor;
mod out;
mod proto;
mod services;
mod wire;

use std::time::Duration;

use koompi_network::NetworkService;
use koompi_power::PowerService;
use koompi_service::PollRate;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::oneshot;

use crate::actor::{Job, Jobs};
use crate::out::Out;
use crate::proto::{ErrorCode, Failure, Outcome, Request};
use crate::services::{NetworkCmd, PowerCmd};

const SERVICES: &[&str] = &["network", "power"];
const DEBOUNCE_BASE: Duration = Duration::from_millis(100);
const DEBOUNCE_ENV: &str = "KOOMPI_SHELLD_DEBOUNCE_MS";
const MAX_LINE: usize = 256 * 1024;

struct Shelld {
    out: Out,
    rate: PollRate,
    debounce: Duration,
    network: Option<Jobs<NetworkService>>,
    power: Option<Jobs<PowerService>>,
}

impl Shelld {
    fn new(out: Out) -> Self {
        Self {
            out,
            rate: PollRate::NORMAL,
            debounce: debounce(),
            network: None,
            power: None,
        }
    }

    /// `Ok(true)` means carry on reading stdin.
    async fn dispatch(&mut self, request: Request) -> bool {
        let id = request.id;
        match request.cmd.as_str() {
            "ping" => self.out.send(proto::reply(id, Ok(()))),
            "subscribe" => self.subscribe(&request),
            "unsubscribe" => {
                let outcome = self.unsubscribe(&request);
                self.out.send(proto::reply(id, outcome));
            }
            "set_poll_rate" => {
                let outcome = self.set_poll_rate(&request);
                self.out.send(proto::reply(id, outcome));
            }
            "quit" => {
                self.out.send(proto::reply(id, Ok(())));
                self.out.drain().await;
                return false;
            }
            _ => self.route(&request),
        }
        true
    }

    fn subscribe(&mut self, request: &Request) {
        let names = match request.str_list("services") {
            Ok(names) => names,
            Err(failure) => return self.out.send(proto::reply(request.id, Err(failure))),
        };

        // one signal per named service, whether it was started here or was already
        // running and only owes a fresh snapshot
        let mut ready = Vec::new();
        for name in &names {
            let signal = match name.as_str() {
                "network" => start::<NetworkService>(
                    &mut self.network,
                    &self.out,
                    self.rate,
                    self.debounce,
                ),
                "power" => {
                    start::<PowerService>(&mut self.power, &self.out, self.rate, self.debounce)
                }
                other => {
                    let failure = Failure::new(ErrorCode::UnknownService, other);
                    return self.out.send(proto::reply(request.id, Err(failure)));
                }
            };
            ready.push(signal);
        }

        // the reply owes its place behind every state this subscribe produced, and waiting
        // for them here would stop the daemon reading its own stdin
        let id = request.id;
        let out = self.out.clone();
        tokio::spawn(async move {
            for signal in ready {
                let _ = signal.await;
            }
            out.send(proto::reply(id, Ok(())));
        });
    }

    fn unsubscribe(&mut self, request: &Request) -> Outcome {
        for name in request.str_list("services")? {
            match name.as_str() {
                // dropping the sender closes the actor's channel, which drops the service
                "network" => self.network = None,
                "power" => self.power = None,
                other => return Err(Failure::new(ErrorCode::UnknownService, other)),
            }
        }
        Ok(())
    }

    fn set_poll_rate(&mut self, request: &Request) -> Outcome {
        let factor = u32::try_from(request.u64("factor")?).unwrap_or(u32::MAX);
        self.rate = PollRate::new(factor);

        if let Some(jobs) = &self.network {
            let _ = jobs.try_send(Job::SetPollRate(self.rate));
        }
        if let Some(jobs) = &self.power {
            let _ = jobs.try_send(Job::SetPollRate(self.rate));
        }
        Ok(())
    }

    fn route(&self, request: &Request) {
        let id = request.id;
        let service = match request.service() {
            Ok(service) => service,
            Err(failure) => return self.out.send(proto::reply(id, Err(failure))),
        };

        let outcome = match service {
            "network" => job::<NetworkService>(&self.network, request, NetworkCmd::parse),
            "power" => job::<PowerService>(&self.power, request, PowerCmd::parse),
            other => Err(Failure::new(ErrorCode::UnknownService, other)),
        };

        // a routed command is answered by the service that ran it, so only a failure to
        // hand it over is replied to here
        if let Err(failure) = outcome {
            self.out.send(proto::reply(id, Err(failure)));
        }
    }
}

/// Starts the service if it is not running, and either way returns the signal that
/// fires once its state is on the wire.
fn start<M: actor::Managed>(
    slot: &mut Option<Jobs<M>>,
    out: &Out,
    rate: PollRate,
    debounce: Duration,
) -> oneshot::Receiver<()> {
    if let Some(jobs) = slot {
        let (tx, rx) = oneshot::channel();
        if jobs.try_send(Job::Resend(tx)).is_err() {
            let (tx, rx) = oneshot::channel();
            let _ = tx.send(());
            return rx;
        }
        return rx;
    }

    let (jobs, ready) = actor::spawn::<M>(out.clone(), rate, debounce);
    *slot = Some(jobs);
    ready
}

fn job<M: actor::Managed>(
    slot: &Option<Jobs<M>>,
    request: &Request,
    parse: fn(&Request) -> Result<M::Cmd, Failure>,
) -> Outcome {
    let jobs = slot
        .as_ref()
        .ok_or_else(|| Failure::new(ErrorCode::NotSubscribed, M::NAME))?;

    let cmd = match request.cmd.as_str() {
        "get_state" => {
            return jobs
                .try_send(Job::GetState { id: request.id })
                .map_err(|_| Failure::new(ErrorCode::Unavailable, M::NAME))
        }
        _ => parse(request)?,
    };

    jobs.try_send(Job::Apply {
        id: request.id,
        cmd,
    })
    .map_err(|_| Failure::new(ErrorCode::Unavailable, M::NAME))
}

fn debounce() -> Duration {
    std::env::var(DEBOUNCE_ENV)
        .ok()
        .and_then(|ms| ms.parse().ok())
        .map(Duration::from_millis)
        .unwrap_or(DEBOUNCE_BASE)
}

#[tokio::main]
async fn main() {
    let out = Out::stdout();
    out.send(proto::hello(SERVICES));

    let mut shelld = Shelld::new(out.clone());
    let mut lines = BufReader::new(tokio::io::stdin()).lines();

    while let Ok(Some(line)) = lines.next_line().await {
        if line.len() > MAX_LINE {
            let failure = Failure::new(ErrorCode::Malformed, "line over 256 KiB");
            out.send(proto::reply(None, Err(failure)));
            continue;
        }

        match Request::parse(&line) {
            Ok(None) => {}
            Ok(Some(request)) => {
                if !shelld.dispatch(request).await {
                    return;
                }
            }
            Err((id, failure)) => out.send(proto::reply(id, Err(failure))),
        }
    }

    // stdin closed: the shell went away, and so does everything we opened on its behalf
    out.drain().await;
}
