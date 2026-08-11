//! This seat as one value, the fields `loginctl show-session` and `loginctl show-seat`
//! print.

use crate::capability::Capabilities;
use crate::inhibit::What;
use crate::props::{self, Props};
use koompi_service::PollRate;

/// The login session this process belongs to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionInfo {
    pub id: String,
    pub path: String,
    pub name: String,
    pub uid: u32,
    /// `user`, `greeter`, `lock-screen`, `manager` and the rest. Kept as logind spells
    /// it: the list has grown twice and a consumer that shows it is not helped by an
    /// enum that drops the newest member.
    pub class: String,
    /// `wayland`, `x11`, `tty`, `unspecified`.
    pub kind: String,
    /// `online`, `active`, `closing`.
    pub state: String,
    pub active: bool,
    /// What the session last told logind about its lock screen, via `SetLockedHint`.
    /// It is a hint: nothing enforces that it matches what is on the glass.
    pub locked_hint: bool,
    pub idle_hint: bool,
    pub can_lock: bool,
    pub can_idle: bool,
    pub desktop: String,
    pub tty: String,
    pub vt: u32,
    pub remote: bool,
    /// The PAM service that opened the session, `sddm` here.
    pub service: String,
    /// The scope unit that holds every process in the session.
    pub scope: String,
    /// The process logind kills when the scope is terminated. Under a display manager
    /// this is the DM's helper, not the compositor, which is the whole of `3d2957e5`.
    pub leader: u32,
    pub seat: Option<String>,
    pub seat_path: Option<String>,
}

impl SessionInfo {
    pub fn from_props(path: &str, p: &Props) -> Self {
        let seat = props::reference(p, "Seat");
        Self {
            id: props::string(p, "Id").unwrap_or_default(),
            path: path.to_owned(),
            name: props::string(p, "Name").unwrap_or_default(),
            uid: user_uid(p),
            class: props::string(p, "Class").unwrap_or_default(),
            kind: props::string(p, "Type").unwrap_or_default(),
            state: props::string(p, "State").unwrap_or_default(),
            active: props::boolean(p, "Active").unwrap_or(false),
            locked_hint: props::boolean(p, "LockedHint").unwrap_or(false),
            idle_hint: props::boolean(p, "IdleHint").unwrap_or(false),
            can_lock: props::boolean(p, "CanLock").unwrap_or(false),
            can_idle: props::boolean(p, "CanIdle").unwrap_or(false),
            desktop: props::string(p, "Desktop").unwrap_or_default(),
            tty: props::string(p, "TTY").unwrap_or_default(),
            vt: props::uint32(p, "VTNr").unwrap_or(0),
            remote: props::boolean(p, "Remote").unwrap_or(false),
            service: props::string(p, "Service").unwrap_or_default(),
            scope: props::string(p, "Scope").unwrap_or_default(),
            leader: props::uint32(p, "Leader").unwrap_or(0),
            seat: seat.as_ref().map(|(id, _)| id.clone()),
            seat_path: seat.map(|(_, path)| path),
        }
    }

    /// True where terminating this session's scope would SIGTERM a display manager's
    /// helper rather than the compositor. `dots/.local/bin/koompi-logout` is the
    /// answer; see `crate::action::Call::strands_the_seat`.
    pub fn leader_is_display_manager_helper(&self) -> bool {
        matches!(self.service.as_str(), "sddm" | "gdm" | "lightdm" | "lxdm")
    }
}

/// `User` is `(uo)` rather than `(so)`, so it needs its own read.
fn user_uid(p: &Props) -> u32 {
    use zvariant::Value;
    let Some(value) = p.get("User") else {
        return 0;
    };
    let Value::Structure(fields) = &**value else {
        return 0;
    };
    match fields.fields() {
        [Value::U32(uid), _] => *uid,
        _ => 0,
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SeatInfo {
    pub id: String,
    pub path: String,
    /// Whether the seat has a graphics device at all. A shell that draws should not
    /// start on a seat that answers false.
    pub can_graphical: bool,
    pub can_tty: bool,
    pub idle_hint: bool,
    pub active_session: Option<String>,
    pub sessions: Vec<String>,
}

impl SeatInfo {
    pub fn from_props(path: &str, p: &Props) -> Self {
        Self {
            id: props::string(p, "Id").unwrap_or_default(),
            path: path.to_owned(),
            can_graphical: props::boolean(p, "CanGraphical").unwrap_or(false),
            can_tty: props::boolean(p, "CanTTY").unwrap_or(false),
            idle_hint: props::boolean(p, "IdleHint").unwrap_or(false),
            active_session: props::reference(p, "ActiveSession").map(|(id, _)| id),
            sessions: props::references(p, "Sessions")
                .into_iter()
                .map(|(id, _)| id)
                .collect(),
        }
    }
}

/// Everything a consumer can read now, as one sample.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionState {
    pub session: SessionInfo,
    /// A session with no seat is a working session: `loginctl list-sessions` shows
    /// this user's `manager` session with no seat at all.
    pub seat: Option<SeatInfo>,
    pub capabilities: Capabilities,
    /// logind is between `PrepareForSleep(true)` and the machine actually sleeping.
    pub preparing_for_sleep: bool,
    pub preparing_for_shutdown: bool,
    /// What is blocked right now, across every inhibitor on the system, which is why
    /// `capabilities.suspend` can read `inhibited`.
    pub block_inhibited: What,
    pub delay_inhibited: What,
    pub poll_rate: PollRate,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use zvariant::{ObjectPath, OwnedValue, Structure, Value};

    fn props(entries: Vec<(&str, Value<'static>)>) -> Props {
        entries
            .into_iter()
            .map(|(key, value)| (key.to_owned(), OwnedValue::try_from(value).unwrap()))
            .collect()
    }

    fn reference(id: &str, path: &'static str) -> Value<'static> {
        Value::from(Structure::from((
            id.to_owned(),
            ObjectPath::try_from(path).unwrap(),
        )))
    }

    /// The literal reply this seat's session 2 gives to `GetAll`, abridged to the
    /// fields a consumer reads.
    #[test]
    fn this_seats_session_decodes_to_what_loginctl_show_session_prints() {
        let info = SessionInfo::from_props(
            "/org/freedesktop/login1/session/_32",
            &props(vec![
                ("Id", Value::from("2")),
                ("Name", Value::from("userx")),
                (
                    "User",
                    Value::from(Structure::from((
                        1000u32,
                        ObjectPath::try_from("/org/freedesktop/login1/user/_1000").unwrap(),
                    ))),
                ),
                ("Class", Value::from("user")),
                ("Type", Value::from("wayland")),
                ("State", Value::from("active")),
                ("Active", Value::from(true)),
                ("LockedHint", Value::from(false)),
                ("IdleHint", Value::from(false)),
                ("CanLock", Value::from(true)),
                ("CanIdle", Value::from(true)),
                ("Desktop", Value::from("KOOMPI:Hyprland")),
                ("TTY", Value::from("tty1")),
                ("VTNr", Value::from(1u32)),
                ("Remote", Value::from(false)),
                ("Service", Value::from("sddm")),
                ("Scope", Value::from("session-2.scope")),
                ("Leader", Value::from(989u32)),
                (
                    "Seat",
                    reference("seat0", "/org/freedesktop/login1/seat/seat0"),
                ),
            ]),
        );

        assert_eq!(info.id, "2");
        assert_eq!(info.uid, 1000);
        assert_eq!(info.class, "user");
        assert_eq!(info.kind, "wayland");
        assert_eq!(info.state, "active");
        assert!(info.active);
        assert!(!info.locked_hint);
        assert_eq!(info.seat.as_deref(), Some("seat0"));
        assert_eq!(info.vt, 1);
        assert_eq!(info.leader, 989);
        assert_eq!(info.scope, "session-2.scope");
        assert!(info.leader_is_display_manager_helper());
    }

    /// `loginctl list-sessions` shows session 3, class `manager`, with no seat. It
    /// must decode rather than fail, and it must not be mistaken for a DM session.
    #[test]
    fn the_seatless_manager_session_decodes_with_no_seat() {
        let info = SessionInfo::from_props(
            "/org/freedesktop/login1/session/_33",
            &props(vec![
                ("Id", Value::from("3")),
                ("Class", Value::from("manager")),
                ("Type", Value::from("unspecified")),
                ("Seat", reference("", "/")),
                ("Service", Value::from("systemd-user")),
                ("Leader", Value::from(1035u32)),
            ]),
        );
        assert_eq!(info.class, "manager");
        assert_eq!(info.seat, None);
        assert_eq!(info.seat_path, None);
        assert!(!info.leader_is_display_manager_helper());
    }

    #[test]
    fn an_empty_reply_decodes_to_empty_fields_rather_than_failing() {
        let info = SessionInfo::from_props("/x", &HashMap::new());
        assert!(info.id.is_empty());
        assert_eq!(info.uid, 0);
        assert!(!info.active);
        assert_eq!(info.seat, None);
    }

    #[test]
    fn this_seat_decodes_to_what_loginctl_show_seat_prints() {
        let seat = SeatInfo::from_props(
            "/org/freedesktop/login1/seat/seat0",
            &props(vec![
                ("Id", Value::from("seat0")),
                ("CanGraphical", Value::from(true)),
                ("CanTTY", Value::from(true)),
                ("IdleHint", Value::from(false)),
                (
                    "ActiveSession",
                    reference("2", "/org/freedesktop/login1/session/_32"),
                ),
                (
                    "Sessions",
                    Value::from(zvariant::Array::from(vec![reference(
                        "2",
                        "/org/freedesktop/login1/session/_32",
                    )])),
                ),
            ]),
        );
        assert_eq!(seat.id, "seat0");
        assert!(seat.can_graphical);
        assert_eq!(seat.active_session.as_deref(), Some("2"));
        assert_eq!(seat.sessions, ["2"]);
    }
}
