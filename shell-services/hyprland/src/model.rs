//! The shapes Hyprland's `j/` queries answer with, as the shell consumes them.

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::binds::Keybind;
use crate::xkb::Keyboard;

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(default)]
pub struct WorkspaceRef {
    pub id: i64,
    pub name: String,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(default)]
pub struct Client {
    pub address: String,
    pub mapped: bool,
    pub hidden: bool,
    pub at: [i32; 2],
    pub size: [i32; 2],
    pub workspace: WorkspaceRef,
    pub floating: bool,
    pub monitor: i64,
    pub class: String,
    pub title: String,
    #[serde(rename = "initialClass")]
    pub initial_class: String,
    #[serde(rename = "initialTitle")]
    pub initial_title: String,
    pub pid: i64,
    pub xwayland: bool,
    pub pinned: bool,
    pub fullscreen: i64,
    pub grouped: Vec<String>,
    pub tags: Vec<String>,
    pub swallowing: String,
    #[serde(rename = "focusHistoryID")]
    pub focus_history_id: i64,
    #[serde(rename = "inhibitingIdle")]
    pub inhibiting_idle: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(default)]
pub struct Workspace {
    pub id: i64,
    pub name: String,
    pub monitor: String,
    #[serde(rename = "monitorID")]
    pub monitor_id: i64,
    pub windows: i64,
    pub hasfullscreen: bool,
    pub lastwindow: String,
    pub lastwindowtitle: String,
    pub ispersistent: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(default)]
pub struct Monitor {
    pub id: i64,
    pub name: String,
    pub description: String,
    pub make: String,
    pub model: String,
    pub serial: String,
    pub width: i32,
    pub height: i32,
    #[serde(rename = "refreshRate")]
    pub refresh_rate: f64,
    pub x: i32,
    pub y: i32,
    #[serde(rename = "activeWorkspace")]
    pub active_workspace: WorkspaceRef,
    #[serde(rename = "specialWorkspace")]
    pub special_workspace: WorkspaceRef,
    pub reserved: [i32; 4],
    pub scale: f64,
    pub transform: i64,
    pub focused: bool,
    #[serde(rename = "dpmsStatus")]
    pub dpms_status: bool,
    pub vrr: bool,
    pub disabled: bool,
    #[serde(rename = "mirrorOf")]
    pub mirror_of: String,
    #[serde(rename = "availableModes")]
    pub available_modes: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(default)]
pub struct LayerSurface {
    pub address: String,
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
    pub namespace: String,
    pub pid: i64,
}

/// One monitor's layer shells, keyed by the `zwlr_layer_shell_v1` level as a string,
/// which is how the compositor serialises it.
#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(default)]
pub struct MonitorLayers {
    pub levels: BTreeMap<String, Vec<LayerSurface>>,
}

/// Everything `HyprlandData.qml:15-24`, `HyprlandKeybinds.qml:17-18` and
/// `HyprlandXkb.qml:16-19` publish between them, in one value.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct HyprlandState {
    pub windows: Vec<Client>,
    pub workspaces: Vec<Workspace>,
    pub active_workspace: Option<Workspace>,
    pub active_window: Option<Client>,
    pub monitors: Vec<Monitor>,
    pub layers: BTreeMap<String, MonitorLayers>,
    pub keybinds: Vec<Keybind>,
    pub keyboard: Keyboard,
    pub submap: String,
    pub connected: bool,
}

impl HyprlandState {
    pub fn addresses(&self) -> impl Iterator<Item = &str> {
        self.windows.iter().map(|w| w.address.as_str())
    }

    pub fn window_by_address(&self, address: &str) -> Option<&Client> {
        self.windows.iter().find(|w| w.address == address)
    }

    pub fn workspace_by_id(&self, id: i64) -> Option<&Workspace> {
        self.workspaces.iter().find(|w| w.id == id)
    }

    pub fn windows_on_workspace(&self, id: i64) -> impl Iterator<Item = &Client> {
        self.windows.iter().filter(move |w| w.workspace.id == id)
    }

    /// The subset `HyprlandData.qml:157` keeps: special and lock-screen workspaces carry
    /// ids outside 1..=100 and the bar does not draw them. Full list stays in
    /// [`HyprlandState::workspaces`] because that is a drawing decision, not a data one.
    pub fn numbered_workspaces(&self) -> impl Iterator<Item = &Workspace> {
        self.workspaces.iter().filter(|w| (1..=100).contains(&w.id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn clients() -> Vec<Client> {
        serde_json::from_str(include_str!("../tests/fixtures/clients.json")).unwrap()
    }

    #[test]
    fn clients_json_from_this_session_decodes() {
        let windows = clients();
        assert_eq!(windows.len(), 5);

        let chrome = windows
            .iter()
            .find(|w| w.class == "google-chrome")
            .expect("captured session had a chrome window");
        assert_eq!(chrome.address, "0x55946b5f3910");
        assert_eq!(chrome.workspace.id, 9);
        assert_eq!(chrome.size, [1908, 1148]);
        assert_eq!(chrome.pid, 41226);
        assert!(!chrome.xwayland);
    }

    #[test]
    fn lookups_match_the_maps_the_qml_publishes() {
        let state = HyprlandState {
            windows: clients(),
            workspaces: serde_json::from_str(include_str!("../tests/fixtures/workspaces.json"))
                .unwrap(),
            ..Default::default()
        };

        assert_eq!(
            state.window_by_address("0x55946b5f3910").map(|w| &w.class),
            Some(&"google-chrome".to_string())
        );
        assert!(state.window_by_address("0xdeadbeef").is_none());
        assert_eq!(state.addresses().count(), state.windows.len());
        assert_eq!(state.workspace_by_id(1).map(|w| w.name.as_str()), Some("1"));
        assert_eq!(state.windows_on_workspace(9).count(), 1);
    }

    #[test]
    fn special_workspaces_are_kept_but_excluded_from_the_numbered_view() {
        let mut workspaces: Vec<Workspace> =
            serde_json::from_str(include_str!("../tests/fixtures/workspaces.json")).unwrap();
        let real = workspaces.len();
        workspaces.push(Workspace {
            id: -98,
            name: "special:scratch".into(),
            ..Default::default()
        });
        workspaces.push(Workspace {
            id: 2147483646,
            name: "lock".into(),
            ..Default::default()
        });
        let state = HyprlandState {
            workspaces,
            ..Default::default()
        };

        assert_eq!(state.numbered_workspaces().count(), real);
        assert_eq!(state.workspaces.len(), real + 2);
    }

    #[test]
    fn monitor_and_layer_json_from_this_session_decodes() {
        let monitors: Vec<Monitor> =
            serde_json::from_str(include_str!("../tests/fixtures/monitors.json")).unwrap();
        let edp = &monitors[0];
        assert_eq!(edp.name, "eDP-1");
        assert_eq!((edp.width, edp.height), (1920, 1200));
        assert_eq!(edp.active_workspace.id, 1);
        assert!(edp.focused);

        let layers: BTreeMap<String, MonitorLayers> =
            serde_json::from_str(include_str!("../tests/fixtures/layers.json")).unwrap();
        let bar = &layers["eDP-1"].levels["2"][0];
        assert_eq!(bar.namespace, "quickshell:bar");
        assert_eq!(bar.h, 63);
    }

    #[test]
    fn active_window_and_workspace_decode_as_single_objects() {
        let window: Client =
            serde_json::from_str(include_str!("../tests/fixtures/activewindow.json")).unwrap();
        assert_eq!(window.class, "org.wezfurlong.wezterm");
        assert_eq!(window.workspace.id, 1);

        let workspace: Workspace =
            serde_json::from_str(include_str!("../tests/fixtures/activeworkspace.json")).unwrap();
        assert_eq!(workspace.id, 1);
        assert_eq!(workspace.monitor, "eDP-1");
    }
}
