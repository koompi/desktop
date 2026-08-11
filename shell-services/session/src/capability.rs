//! What logind answers when asked whether an operation is possible.
//!
//! `SessionWarnings.qml:47` shells out to `busctl` and greps the reply for
//! `"(yes|challenge)"`. That grep was written against the four forms systemd used to
//! answer with. systemd 261 answers with seven, documented in
//! `org.freedesktop.login1(5)`, and three of the new ones are about inhibitors. The
//! grep reads all three as "cannot", which on this seat is wrong: the shell's own
//! keep-awake inhibitor makes `CanSuspend` answer `inhibited`.

/// One reply to a `Can*` method. Seven documented forms plus whatever systemd adds
/// next, which is kept verbatim rather than collapsed into "no".
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Capability {
    /// Hardware, kernel or drivers do not support the operation.
    Na,
    /// Supported, and the user may execute it without further authentication.
    Yes,
    /// Available, but the user is not allowed to execute it.
    No,
    /// Available after authorization.
    Challenge,
    /// Normally available without authorization, currently inhibited. Possible if
    /// inhibitors are ignored and after authorization.
    Inhibited,
    /// Normally available without authorization, and a held inhibitor disallows it
    /// entirely while it remains active.
    InhibitorBlocked,
    /// Normally available after authorization, and a held inhibitor disallows it
    /// entirely while it remains active.
    ChallengeInhibitorBlocked,
    /// A reply this crate does not model. Never treated as permission.
    Unknown(String),
}

impl Capability {
    pub fn from_reply(reply: &str) -> Self {
        match reply {
            "na" => Self::Na,
            "yes" => Self::Yes,
            "no" => Self::No,
            "challenge" => Self::Challenge,
            "inhibited" => Self::Inhibited,
            "inhibitor-blocked" => Self::InhibitorBlocked,
            "challenge-inhibitor-blocked" => Self::ChallengeInhibitorBlocked,
            other => Self::Unknown(other.to_owned()),
        }
    }

    pub fn as_str(&self) -> &str {
        match self {
            Self::Na => "na",
            Self::Yes => "yes",
            Self::No => "no",
            Self::Challenge => "challenge",
            Self::Inhibited => "inhibited",
            Self::InhibitorBlocked => "inhibitor-blocked",
            Self::ChallengeInhibitorBlocked => "challenge-inhibitor-blocked",
            Self::Unknown(reply) => reply,
        }
    }

    /// The hardware can do it at all. `na` is the only answer that says it cannot,
    /// and an unmodelled reply is not read as a yes.
    pub fn supported(&self) -> bool {
        !matches!(self, Self::Na | Self::Unknown(_))
    }

    /// Exactly what `SessionWarnings.qml:47` greps for, kept so a consumer can port
    /// the QML's behaviour unchanged and then decide to stop.
    pub fn offered(&self) -> bool {
        matches!(self, Self::Yes | Self::Challenge)
    }

    /// An inhibitor is standing in the way right now. A menu entry can stay enabled
    /// and say why instead of vanishing.
    pub fn inhibited(&self) -> bool {
        matches!(
            self,
            Self::Inhibited | Self::InhibitorBlocked | Self::ChallengeInhibitorBlocked
        )
    }

    /// The user will be asked to authenticate.
    pub fn needs_auth(&self) -> bool {
        matches!(self, Self::Challenge | Self::ChallengeInhibitorBlocked)
    }

    /// The operation can be made to happen: now, after a polkit prompt, or by asking
    /// logind to ignore inhibitors. The `*-blocked` forms are excluded because the man
    /// page says the user is not allowed to execute them while the inhibitor is held.
    pub fn permitted(&self) -> bool {
        matches!(self, Self::Yes | Self::Challenge | Self::Inhibited)
    }
}

/// The six capabilities `SessionWarnings.qml` and a power menu need, read together so
/// they cannot disagree about when they were sampled.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Capabilities {
    pub power_off: Capability,
    pub reboot: Capability,
    pub suspend: Capability,
    pub hibernate: Capability,
    pub hybrid_sleep: Capability,
    pub suspend_then_hibernate: Capability,
}

impl Capabilities {
    pub fn get(&self, action: crate::PowerAction) -> &Capability {
        use crate::PowerAction::*;
        match action {
            PowerOff => &self.power_off,
            Reboot => &self.reboot,
            Suspend => &self.suspend,
            Hibernate => &self.hibernate,
            HybridSleep => &self.hybrid_sleep,
            SuspendThenHibernate => &self.suspend_then_hibernate,
        }
    }

    pub fn iter(&self) -> impl Iterator<Item = (crate::PowerAction, &Capability)> {
        crate::PowerAction::ALL
            .into_iter()
            .map(|action| (action, self.get(action)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_reply_form_systemd_261_documents_round_trips() {
        let forms = [
            "na",
            "yes",
            "no",
            "challenge",
            "inhibited",
            "inhibitor-blocked",
            "challenge-inhibitor-blocked",
        ];
        for form in forms {
            let parsed = Capability::from_reply(form);
            assert!(
                !matches!(parsed, Capability::Unknown(_)),
                "{form} unmodelled"
            );
            assert_eq!(parsed.as_str(), form);
        }
    }

    #[test]
    fn a_reply_we_do_not_model_is_kept_verbatim_and_grants_nothing() {
        let next = Capability::from_reply("yes-but-only-on-tuesdays");
        assert_eq!(next.as_str(), "yes-but-only-on-tuesdays");
        assert!(!next.supported());
        assert!(!next.offered());
        assert!(!next.permitted());
        assert!(!next.inhibited());
        assert!(!next.needs_auth());
    }

    /// The QML's grep is reproduced, not the type: `offered` must agree with
    /// `grep -qE '"(yes|challenge)"'` on all seven forms, including the three where
    /// agreeing means being wrong.
    #[test]
    fn offered_matches_the_qml_grep_on_every_form_including_where_the_grep_is_wrong() {
        let cases = [
            ("na", false),
            ("yes", true),
            ("no", false),
            ("challenge", true),
            ("inhibited", false),
            ("inhibitor-blocked", false),
            ("challenge-inhibitor-blocked", false),
        ];
        for (reply, grep_says_yes) in cases {
            assert_eq!(
                Capability::from_reply(reply).offered(),
                grep_says_yes,
                "{reply}"
            );
        }
    }

    /// This seat answers `inhibited` to `CanSuspend` because `Idle.qml:53-58` holds a
    /// block inhibitor. The QML would draw suspend as impossible; it is not.
    #[test]
    fn inhibited_is_still_possible_which_is_where_the_qml_grep_gets_it_wrong() {
        let inhibited = Capability::from_reply("inhibited");
        assert!(inhibited.supported());
        assert!(inhibited.inhibited());
        assert!(inhibited.permitted());
        assert!(!inhibited.offered());

        let blocked = Capability::from_reply("inhibitor-blocked");
        assert!(blocked.supported());
        assert!(blocked.inhibited());
        assert!(!blocked.permitted());

        let both = Capability::from_reply("challenge-inhibitor-blocked");
        assert!(both.needs_auth());
        assert!(both.inhibited());
        assert!(!both.permitted());
    }

    #[test]
    fn na_is_unsupported_and_nothing_else_is() {
        assert!(!Capability::from_reply("na").supported());
        assert!(!Capability::from_reply("na").permitted());
        for form in ["yes", "no", "challenge", "inhibited", "inhibitor-blocked"] {
            assert!(Capability::from_reply(form).supported(), "{form}");
        }
    }
}
