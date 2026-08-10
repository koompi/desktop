//! What each service adds to the shared lifecycle in [`crate::actor`]: how it connects,
//! how its state reaches the wire, and the commands it takes.

use std::sync::Arc;
use std::time::Duration;

use koompi_hyprland::{HyprlandService, HyprlandState};
use koompi_network::{NetworkService, NetworkState};
use koompi_power::{PowerConfig, PowerService, PowerState, Profile};
use koompi_service::{PollRate, Service};
use serde_json::Value;
use tokio::sync::watch;

use crate::actor::Managed;
use crate::proto::{ErrorCode, Failure, Outcome, Request};
use crate::wire;

pub enum NetworkCmd {
    SetWirelessEnabled(bool),
    RequestScan,
    Connect {
        path: String,
        passphrase: Option<String>,
    },
    Disconnect,
}

impl NetworkCmd {
    pub fn parse(request: &Request) -> Result<Self, Failure> {
        match request.cmd.as_str() {
            "set_wireless_enabled" => Ok(Self::SetWirelessEnabled(request.bool("enabled")?)),
            "request_scan" => Ok(Self::RequestScan),
            "connect" => Ok(Self::Connect {
                path: request.str("path")?.to_owned(),
                passphrase: request.opt_str("passphrase")?.map(str::to_owned),
            }),
            "disconnect" => Ok(Self::Disconnect),
            other => Err(Failure::new(ErrorCode::UnknownCommand, other)),
        }
    }
}

impl Managed for NetworkService {
    type State = NetworkState;
    type Cmd = NetworkCmd;

    const NAME: &'static str = "network";

    async fn connect(rate: PollRate) -> koompi_service::Result<Self> {
        NetworkService::connect(rate).await
    }

    fn watch(&self) -> watch::Receiver<NetworkState> {
        self.subscribe()
    }

    fn encode(state: &NetworkState) -> Value {
        wire::network(state)
    }

    fn healthy(state: &NetworkState) -> bool {
        state.available
    }

    fn set_poll_rate(&self, rate: PollRate) {
        NetworkService::set_poll_rate(self, rate);
    }

    async fn apply(self: Arc<Self>, cmd: NetworkCmd) -> Outcome {
        match cmd {
            NetworkCmd::SetWirelessEnabled(enabled) => {
                self.set_wireless_enabled(enabled).await?;
            }
            NetworkCmd::RequestScan => self.request_scan().await?,
            NetworkCmd::Disconnect => self.disconnect().await?,
            NetworkCmd::Connect { path, passphrase } => {
                // resolved against the snapshot the consumer was looking at; a path from a
                // scan that has since been replaced is the consumer's cue to rescan
                let access_point = self
                    .state()
                    .wifi
                    .networks
                    .into_iter()
                    .find(|ap| ap.path == path)
                    .ok_or_else(|| Failure::new(ErrorCode::UnknownAccessPoint, path))?;

                self.connect_to(&access_point, passphrase.as_deref()).await?;
            }
        }
        Ok(())
    }
}

pub enum PowerCmd {
    SetChargeThresholdEnabled(bool),
    SetProfile(Profile),
}

impl PowerCmd {
    pub fn parse(request: &Request) -> Result<Self, Failure> {
        match request.cmd.as_str() {
            "set_charge_threshold_enabled" => {
                Ok(Self::SetChargeThresholdEnabled(request.bool("enabled")?))
            }
            "set_profile" => {
                let name = request.str("profile")?;
                Profile::parse(name)
                    .map(Self::SetProfile)
                    .ok_or_else(|| Failure::new(ErrorCode::BadRequest, format!("no profile {name}")))
            }
            other => Err(Failure::new(ErrorCode::UnknownCommand, other)),
        }
    }
}

impl Managed for PowerService {
    type State = PowerState;
    type Cmd = PowerCmd;

    const NAME: &'static str = "power";

    async fn connect(_rate: PollRate) -> koompi_service::Result<Self> {
        PowerService::connect(PowerConfig::default()).await
    }

    fn watch(&self) -> watch::Receiver<PowerState> {
        self.subscribe()
    }

    fn encode(state: &PowerState) -> Value {
        wire::power(state)
    }

    async fn apply(self: Arc<Self>, cmd: PowerCmd) -> Outcome {
        match cmd {
            PowerCmd::SetChargeThresholdEnabled(enabled) => {
                self.set_charge_threshold_enabled(enabled).await?
            }
            PowerCmd::SetProfile(profile) => self.set_profile(profile).await?,
        }
        Ok(())
    }
}

/// The compositor is reachable the moment its socket is, but the state behind it is empty
/// until the first query lands. `SessionRestore.qml:182` replays a saved session when it
/// sees no windows, so publishing that empty snapshot would relaunch a desktop that is
/// already open.
const FIRST_QUERY: Duration = Duration::from_secs(2);

/// Read-only. Every write the shell makes to Hyprland is a `dispatch`, which
/// `Quickshell.Hyprland` already owns.
pub enum HyprlandCmd {}

impl HyprlandCmd {
    pub fn parse(request: &Request) -> Result<Self, Failure> {
        Err(Failure::new(ErrorCode::UnknownCommand, request.cmd.clone()))
    }
}

impl Managed for HyprlandService {
    type State = HyprlandState;
    type Cmd = HyprlandCmd;

    const NAME: &'static str = "hyprland";

    async fn connect(rate: PollRate) -> koompi_service::Result<Self> {
        let service = HyprlandService::start(rate).await?;
        tokio::time::timeout(FIRST_QUERY, service.ready())
            .await
            .map_err(|_| {
                koompi_service::Error::Unavailable("hyprland did not answer its socket".into())
            })?;
        Ok(service)
    }

    fn watch(&self) -> watch::Receiver<HyprlandState> {
        self.subscribe()
    }

    fn encode(state: &HyprlandState) -> Value {
        wire::hyprland(state)
    }

    fn healthy(state: &HyprlandState) -> bool {
        state.connected
    }

    fn set_poll_rate(&self, rate: PollRate) {
        HyprlandService::set_poll_rate(self, rate);
    }

    async fn apply(self: Arc<Self>, cmd: HyprlandCmd) -> Outcome {
        match cmd {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(line: &str) -> Request {
        Request::parse(line).unwrap().unwrap()
    }

    fn refused<T>(parsed: Result<T, Failure>) -> ErrorCode {
        let Err(failure) = parsed else {
            panic!("expected a refusal");
        };
        failure.code
    }

    #[test]
    fn a_connect_without_a_path_is_bad_request_not_a_connection_to_nothing() {
        let parsed = NetworkCmd::parse(&request(r#"{"cmd":"connect"}"#));
        assert_eq!(refused(parsed), ErrorCode::BadRequest);
    }

    #[test]
    fn a_connect_may_carry_the_passphrase_and_may_omit_it() {
        let with = NetworkCmd::parse(&request(
            r#"{"cmd":"connect","path":"/ap/1","passphrase":"hunter2"}"#,
        ))
        .unwrap();
        let NetworkCmd::Connect { path, passphrase } = with else {
            panic!("not a connect");
        };
        assert_eq!(path, "/ap/1");
        assert_eq!(passphrase.as_deref(), Some("hunter2"));

        let without = NetworkCmd::parse(&request(r#"{"cmd":"connect","path":"/ap/1"}"#)).unwrap();
        let NetworkCmd::Connect { passphrase, .. } = without else {
            panic!("not a connect");
        };
        assert_eq!(passphrase, None);
    }

    #[test]
    fn a_command_meant_for_another_service_is_unknown_here() {
        let parsed = NetworkCmd::parse(&request(r#"{"cmd":"set_profile","profile":"balanced"}"#));
        assert_eq!(refused(parsed), ErrorCode::UnknownCommand);
    }

    #[test]
    fn hyprland_takes_no_commands_at_all() {
        let parsed = HyprlandCmd::parse(&request(r#"{"cmd":"dispatch","args":"killactive"}"#));
        assert_eq!(refused(parsed), ErrorCode::UnknownCommand);
    }

    #[test]
    fn an_unmodelled_profile_name_is_refused_rather_than_sent_on() {
        let parsed = PowerCmd::parse(&request(r#"{"cmd":"set_profile","profile":"turbo"}"#));
        assert_eq!(refused(parsed), ErrorCode::BadRequest);

        assert!(PowerCmd::parse(&request(r#"{"cmd":"set_profile","profile":"power-saver"}"#)).is_ok());
    }
}
