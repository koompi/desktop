//! The nine calls that change something, and the one place they are built.
//!
//! Every one of them is built here and sent from one function, so a test that asserts
//! the wire form is asserting the message that would actually go out. Nothing in this
//! module runs without a [`zbus::Connection`], which is why the tests below can cover
//! `PowerOff` on a seat someone is logged into.

use zbus::message::Message;
use zbus::Connection;
use zvariant::ObjectPath;

use crate::proxy::{LOGIN1, MANAGER_IFACE, MANAGER_PATH, SESSION_IFACE};

/// A system-wide action on `org.freedesktop.login1.Manager`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PowerAction {
    PowerOff,
    Reboot,
    Suspend,
    Hibernate,
    HybridSleep,
    SuspendThenHibernate,
}

impl PowerAction {
    pub const ALL: [Self; 6] = [
        Self::PowerOff,
        Self::Reboot,
        Self::Suspend,
        Self::Hibernate,
        Self::HybridSleep,
        Self::SuspendThenHibernate,
    ];

    pub fn member(&self) -> &'static str {
        match self {
            Self::PowerOff => "PowerOff",
            Self::Reboot => "Reboot",
            Self::Suspend => "Suspend",
            Self::Hibernate => "Hibernate",
            Self::HybridSleep => "HybridSleep",
            Self::SuspendThenHibernate => "SuspendThenHibernate",
        }
    }

    /// The `Can*` method that says whether this one would work.
    pub fn can_member(&self) -> &'static str {
        match self {
            Self::PowerOff => "CanPowerOff",
            Self::Reboot => "CanReboot",
            Self::Suspend => "CanSuspend",
            Self::Hibernate => "CanHibernate",
            Self::HybridSleep => "CanHybridSleep",
            Self::SuspendThenHibernate => "CanSuspendThenHibernate",
        }
    }
}

/// An action on this session's own `org.freedesktop.login1.Session` object.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionAction {
    Lock,
    Unlock,
    /// Kills the session scope, and with it the session leader.
    ///
    /// Under SDDM the leader is `sddm-helper`, so this is the call that stranded this
    /// seat on a black screen at commit `3d2957e5`. See `Call::strands_the_seat`.
    Terminate,
}

impl SessionAction {
    pub fn member(&self) -> &'static str {
        match self {
            Self::Lock => "Lock",
            Self::Unlock => "Unlock",
            Self::Terminate => "Terminate",
        }
    }
}

/// A built method call: destination, path, interface, member and body, before any of
/// it reaches a bus.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Call {
    pub destination: &'static str,
    pub path: String,
    pub interface: &'static str,
    pub member: &'static str,
    /// `Some` for the manager actions, which take `in b interactive`; `None` for the
    /// session actions, which take no arguments.
    pub interactive: Option<bool>,
}

impl Call {
    /// `interactive` is logind's own flag: false fails on a polkit challenge, true
    /// lets the agent prompt the user.
    pub fn power(action: PowerAction, interactive: bool) -> Self {
        Self {
            destination: LOGIN1,
            path: MANAGER_PATH.to_owned(),
            interface: MANAGER_IFACE,
            member: action.member(),
            interactive: Some(interactive),
        }
    }

    pub fn session(action: SessionAction, session_path: &str) -> Self {
        Self {
            destination: LOGIN1,
            path: session_path.to_owned(),
            interface: SESSION_IFACE,
            member: action.member(),
            interactive: None,
        }
    }

    /// True for the one call this repo has already been bitten by: terminating a
    /// session scope SIGTERMs its leader, and under a display manager the leader is
    /// the DM's helper rather than the compositor. `dots/.local/bin/koompi-logout`
    /// exists because of it and gates the sweep on the leader already being gone.
    pub fn strands_the_seat(&self) -> bool {
        self.interface == SESSION_IFACE && self.member == SessionAction::Terminate.member()
            || self.interface == MANAGER_IFACE
                && matches!(
                    self.member,
                    "TerminateSession" | "TerminateUser" | "TerminateSeat"
                )
    }

    /// The message that would go on the bus. Building it touches nothing.
    pub fn message(&self) -> zbus::Result<Message> {
        let path = ObjectPath::try_from(self.path.as_str())?;
        let builder = Message::method_call(&path, self.member)?
            .destination(self.destination)?
            .interface(self.interface)?;
        match self.interactive {
            Some(interactive) => builder.build(&(interactive,)),
            None => builder.build(&()),
        }
    }

    /// The only route from this crate to a method that changes the machine.
    pub async fn send(&self, conn: &Connection) -> crate::Result<()> {
        match self.interactive {
            Some(interactive) => {
                conn.call_method(
                    Some(self.destination),
                    self.path.as_str(),
                    Some(self.interface),
                    self.member,
                    &(interactive,),
                )
                .await?
            }
            None => {
                conn.call_method(
                    Some(self.destination),
                    self.path.as_str(),
                    Some(self.interface),
                    self.member,
                    &(),
                )
                .await?
            }
        };
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SESSION_PATH: &str = "/org/freedesktop/login1/session/_32";

    fn parts(call: &Call) -> (String, String, String, String) {
        let message = call.message().unwrap();
        let header = message.header();
        (
            header.destination().unwrap().to_string(),
            header.path().unwrap().to_string(),
            header.interface().unwrap().to_string(),
            header.member().unwrap().to_string(),
        )
    }

    /// Every manager action, built and inspected without a bus. This is as far as this
    /// job is allowed to take `PowerOff` on a seat with a user logged into it.
    #[test]
    fn every_power_action_builds_the_message_systemctl_would_send() {
        for action in PowerAction::ALL {
            let call = Call::power(action, false);
            let (destination, path, interface, member) = parts(&call);
            assert_eq!(destination, "org.freedesktop.login1");
            assert_eq!(path, "/org/freedesktop/login1");
            assert_eq!(interface, "org.freedesktop.login1.Manager");
            assert_eq!(member, action.member());

            let message = call.message().unwrap();
            assert_eq!(message.body().signature().to_string(), "b");
            assert!(!message.body().deserialize::<bool>().unwrap());
            assert!(!call.strands_the_seat());
        }
    }

    #[test]
    fn the_interactive_flag_is_the_body_and_nothing_else_is() {
        let message = Call::power(PowerAction::Suspend, true).message().unwrap();
        assert_eq!(message.body().signature().to_string(), "b");
        assert!(message.body().deserialize::<bool>().unwrap());
    }

    #[test]
    fn the_six_actions_and_their_capability_queries_line_up() {
        for action in PowerAction::ALL {
            assert_eq!(action.can_member(), format!("Can{}", action.member()));
        }
    }

    #[test]
    fn session_actions_land_on_this_sessions_own_object_with_an_empty_body() {
        for action in [
            SessionAction::Lock,
            SessionAction::Unlock,
            SessionAction::Terminate,
        ] {
            let call = Call::session(action, SESSION_PATH);
            let (destination, path, interface, member) = parts(&call);
            assert_eq!(destination, "org.freedesktop.login1");
            assert_eq!(path, SESSION_PATH);
            assert_eq!(interface, "org.freedesktop.login1.Session");
            assert_eq!(member, action.member());
            assert_eq!(call.message().unwrap().body().signature().to_string(), "");
        }
    }

    /// `loginctl terminate-session $XDG_SESSION_ID` is this message. The flag exists so
    /// a consumer cannot reach it without being told what it does.
    #[test]
    fn terminate_is_flagged_as_the_call_that_stranded_this_seat_and_lock_is_not() {
        assert!(Call::session(SessionAction::Terminate, SESSION_PATH).strands_the_seat());
        assert!(!Call::session(SessionAction::Lock, SESSION_PATH).strands_the_seat());
        assert!(!Call::session(SessionAction::Unlock, SESSION_PATH).strands_the_seat());

        let manager_terminate = Call {
            destination: LOGIN1,
            path: MANAGER_PATH.to_owned(),
            interface: MANAGER_IFACE,
            member: "TerminateSession",
            interactive: None,
        };
        assert!(manager_terminate.strands_the_seat());
    }

    #[test]
    fn a_path_that_is_not_an_object_path_fails_to_build_rather_than_going_out() {
        let call = Call::session(SessionAction::Lock, "not a path");
        assert!(call.message().is_err());
    }
}
