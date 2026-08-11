//! D01 event stream, D02 keybinds, D03 keyboard layout: one persistent socket2
//! subscription and socket1 queries in place of six respawned `hyprctl -j` processes.
//!
//! `HyprlandData.qml:99-107` refetches all six queries behind a 30 ms debounce on every
//! event, at six processes a time. Here the debounce stays, scaled by [`PollRate`], and
//! only what the event invalidated is requeried. Nothing in this crate spawns a process.
//!
//! ```no_run
//! use koompi_hyprland::HyprlandService;
//! use koompi_service::{PollRate, Service};
//!
//! # async fn run() -> koompi_service::Result<()> {
//! let hyprland = HyprlandService::start(PollRate::NORMAL).await?;
//! let state = hyprland.ready().await;
//! println!("{} workspaces", state.workspaces.len());
//! # Ok(())
//! # }
//! ```

pub mod binds;
pub mod event;
pub mod ipc;
pub mod model;
pub mod service;
pub mod xkb;

pub use binds::{categories_of, parse_binds, Keybind};
pub use event::{refresh_for, Event, Refresh};
pub use ipc::Ipc;
pub use model::{
    Client, HyprlandState, LayerSurface, Monitor, MonitorLayers, Workspace, WorkspaceRef,
};
pub use service::HyprlandService;
pub use xkb::{Keyboard, LayoutIndex};
