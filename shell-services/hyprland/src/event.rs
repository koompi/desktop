//! D01. What arrives on `.socket2.sock`, and what each line actually invalidates.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Event {
    pub name: String,
    pub data: String,
}

impl Event {
    pub fn parse(line: &str) -> Option<Self> {
        let (name, data) = line.split_once(">>")?;
        if name.is_empty() {
            return None;
        }
        Some(Self {
            name: name.to_string(),
            data: data.to_string(),
        })
    }
}

/// Which queries a given event makes stale. `HyprlandData.qml:71-77` refetches all six on
/// every event because six processes cost the same whether one or all are needed; over a
/// socket the cheapest correct answer is to fetch what changed.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Refresh {
    pub clients: bool,
    pub workspaces: bool,
    pub active_window: bool,
    pub monitors: bool,
    pub layers: bool,
    pub binds: bool,
    pub devices: bool,
}

impl Refresh {
    pub const ALL: Self = Self {
        clients: true,
        workspaces: true,
        active_window: true,
        monitors: true,
        layers: true,
        binds: true,
        devices: true,
    };

    pub const NONE: Self = Self {
        clients: false,
        workspaces: false,
        active_window: false,
        monitors: false,
        layers: false,
        binds: false,
        devices: false,
    };

    pub fn merge(&mut self, other: Self) {
        self.clients |= other.clients;
        self.workspaces |= other.workspaces;
        self.active_window |= other.active_window;
        self.monitors |= other.monitors;
        self.layers |= other.layers;
        self.binds |= other.binds;
        self.devices |= other.devices;
    }

    pub fn is_empty(&self) -> bool {
        *self == Self::NONE
    }
}

pub fn refresh_for(event: &str) -> Refresh {
    let windows = Refresh {
        clients: true,
        active_window: true,
        workspaces: true,
        ..Refresh::NONE
    };

    match event {
        "openwindow" | "closewindow" | "movewindow" | "movewindowv2" => windows,
        "windowtitle" | "windowtitlev2" | "changefloatingmode" | "fullscreen" | "pin"
        | "minimized" | "togglegroup" | "moveintogroup" | "moveoutofgroup" => Refresh {
            clients: true,
            active_window: true,
            ..Refresh::NONE
        },
        "activewindow" | "activewindowv2" => Refresh {
            active_window: true,
            clients: true,
            ..Refresh::NONE
        },
        "workspace" | "workspacev2" | "createworkspace" | "createworkspacev2"
        | "destroyworkspace" | "destroyworkspacev2" | "moveworkspace" | "moveworkspacev2"
        | "renameworkspace" | "activespecial" | "activespecialv2" => Refresh {
            workspaces: true,
            active_window: true,
            ..Refresh::NONE
        },
        "focusedmon" | "focusedmonv2" => Refresh {
            workspaces: true,
            monitors: true,
            active_window: true,
            ..Refresh::NONE
        },
        "monitoradded" | "monitoraddedv2" | "monitorremoved" | "monitorremovedv2" => Refresh {
            monitors: true,
            workspaces: true,
            ..Refresh::NONE
        },
        "openlayer" | "closelayer" => Refresh {
            layers: true,
            ..Refresh::NONE
        },
        "configreloaded" => Refresh::ALL,
        // Carried by the event payload itself, or of no interest to what this crate holds.
        "activelayout" | "submap" | "screencast" | "urgent" | "bell" | "lockgroups"
        | "ignoregrouplock" => Refresh::NONE,
        _ => Refresh::ALL,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_a_real_event_line_on_the_first_separator() {
        let event = Event::parse("workspacev2>>3,3").unwrap();
        assert_eq!(event.name, "workspacev2");
        assert_eq!(event.data, "3,3");

        let title = Event::parse("windowtitlev2>>55946b3f94c0,a>>b").unwrap();
        assert_eq!(title.name, "windowtitlev2");
        assert_eq!(title.data, "55946b3f94c0,a>>b");

        assert_eq!(
            Event::parse("monitoraddedv2>>0,eDP-1,BOE 0x0CE0").unwrap().data,
            "0,eDP-1,BOE 0x0CE0"
        );
        assert!(Event::parse("garbage without separator").is_none());
        assert!(Event::parse(">>orphan").is_none());
    }

    #[test]
    fn a_monitor_event_does_not_refetch_clients() {
        let refresh = refresh_for("monitoradded");
        assert!(refresh.monitors);
        assert!(!refresh.clients);
        assert!(!refresh.layers);
        assert!(!refresh.binds);
    }

    #[test]
    fn a_workspace_switch_does_not_refetch_monitors_or_binds() {
        let refresh = refresh_for("workspacev2");
        assert!(refresh.workspaces);
        assert!(!refresh.monitors);
        assert!(!refresh.binds);
        assert!(!refresh.clients);
    }

    #[test]
    fn config_reload_refetches_everything_including_binds_and_devices() {
        assert_eq!(refresh_for("configreloaded"), Refresh::ALL);
    }

    #[test]
    fn payload_carried_events_query_nothing() {
        for event in ["activelayout", "submap", "screencast", "urgent"] {
            assert!(refresh_for(event).is_empty(), "{event} queried the socket");
        }
    }

    #[test]
    fn an_event_this_crate_has_never_seen_refetches_everything() {
        assert_eq!(refresh_for("somethingnewin057"), Refresh::ALL);
    }

    #[test]
    fn merging_accumulates_and_never_clears() {
        let mut refresh = refresh_for("openlayer");
        refresh.merge(refresh_for("monitoradded"));
        assert!(refresh.layers && refresh.monitors);
        assert!(!refresh.clients);

        refresh.merge(Refresh::NONE);
        assert!(refresh.layers && refresh.monitors);
    }
}
