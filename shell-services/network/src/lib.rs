//! D09 network: the one service with no Quickshell builtin behind it, so the port both
//! shrinks the code and drops the `nmcli` and `awk` dependency.
//!
//! `Network.qml` runs eleven `nmcli` invocations and keeps a twelfth, `nmcli monitor`,
//! alive for the life of the shell, refreshing all of its state on any line that process
//! prints. Here there is one signal subscription on the system bus and a read of only
//! what the signal invalidated: see [`refresh`]. No subprocess is spawned.
//!
//! Three things come out better rather than merely equal:
//!
//! - An SSID is `ay` on the wire, and [`Ssid`] keeps it that way. Going through nmcli's
//!   terse output loses the bytes before the shell ever sees them.
//! - `Connectivity` distinguishes a captive portal from a working link.
//!   `Network.qml:85` opens `nmcheck.gnome.org` because it cannot.
//! - The security label comes from the `Flags` / `WpaFlags` / `RsnFlags` triple, so a
//!   consumer can ask whether a network wants a passphrase or an EAP identity, not just
//!   read the string nmcli would have printed.
//!
//! Writes are implemented and unit-tested; only [`NetworkService::request_scan`] is ever
//! fired, because the shell already triggers it from a button.
//!
//! ```no_run
//! use koompi_network::NetworkService;
//! use koompi_service::{PollRate, Service};
//!
//! # async fn run() -> koompi_service::Result<()> {
//! let network = NetworkService::connect(PollRate::NORMAL).await?;
//! let state = network.state();
//! println!("{} on {}", state.network_name(), state.connectivity.as_str());
//! # Ok(())
//! # }
//! ```

pub mod ap;
pub mod enums;
pub mod model;
mod props;
pub mod proxy;
pub mod refresh;
pub mod settings;
pub mod service;

pub use ap::{strongest_per_ssid, AccessPoint, Security, Ssid};
pub use enums::{ActiveState, Connectivity, DeviceState, DeviceType, NmState, WifiStatus};
pub use model::{ActiveConnection, Device, NetworkState, WifiState, WiredDevice};
pub use refresh::{refresh_for_properties, refresh_for_signal, Refresh};
pub use service::NetworkService;
