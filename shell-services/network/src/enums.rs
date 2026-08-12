//! The NetworkManager enumerations this crate reads, and the QML string each maps back
//! to. The QML never sees these numbers: `Network.qml:196-219` recovers them by
//! substring-matching `nmcli`'s localised-looking words, which is why it cannot tell a
//! captive portal from a working link.

use std::borrow::Cow;

/// `NM_STATE`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum NmState {
    #[default]
    Unknown,
    Asleep,
    Disconnected,
    Disconnecting,
    Connecting,
    ConnectedLocal,
    ConnectedSite,
    ConnectedGlobal,
}

impl NmState {
    pub fn from_u32(value: u32) -> Self {
        match value {
            10 => Self::Asleep,
            20 => Self::Disconnected,
            30 => Self::Disconnecting,
            40 => Self::Connecting,
            50 => Self::ConnectedLocal,
            60 => Self::ConnectedSite,
            70 => Self::ConnectedGlobal,
            _ => Self::Unknown,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::Asleep => "asleep",
            Self::Disconnected => "disconnected",
            Self::Disconnecting => "disconnecting",
            Self::Connecting => "connecting",
            Self::ConnectedLocal => "connected (local)",
            Self::ConnectedSite => "connected (site)",
            Self::ConnectedGlobal => "connected (global)",
        }
    }
}

/// `NM_CONNECTIVITY`. D09 item 7: `Portal` is the value `Network.qml` cannot see, so it
/// opens `nmcheck.gnome.org` at `:85` and hopes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Connectivity {
    #[default]
    Unknown,
    None,
    Portal,
    Limited,
    Full,
}

impl Connectivity {
    pub fn from_u32(value: u32) -> Self {
        match value {
            1 => Self::None,
            2 => Self::Portal,
            3 => Self::Limited,
            4 => Self::Full,
            _ => Self::Unknown,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::None => "none",
            Self::Portal => "portal",
            Self::Limited => "limited",
            Self::Full => "full",
        }
    }

    /// A link that carries packets but not to the internet. `Network.qml:208` folds
    /// both of these into its one `"limited"` string.
    pub fn degraded(&self) -> bool {
        matches!(self, Self::Portal | Self::Limited)
    }
}

/// `NM_DEVICE_TYPE`, narrowed to what this crate acts on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeviceType {
    Ethernet,
    Wifi,
    Other(u32),
}

impl DeviceType {
    pub fn from_u32(value: u32) -> Self {
        match value {
            1 => Self::Ethernet,
            2 => Self::Wifi,
            other => Self::Other(other),
        }
    }
}

/// `NM_DEVICE_STATE`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DeviceState {
    #[default]
    Unknown,
    Unmanaged,
    Unavailable,
    Disconnected,
    Prepare,
    Config,
    NeedAuth,
    IpConfig,
    IpCheck,
    Secondaries,
    Activated,
    Deactivating,
    Failed,
}

impl DeviceState {
    pub fn from_u32(value: u32) -> Self {
        match value {
            10 => Self::Unmanaged,
            20 => Self::Unavailable,
            30 => Self::Disconnected,
            40 => Self::Prepare,
            50 => Self::Config,
            60 => Self::NeedAuth,
            70 => Self::IpConfig,
            80 => Self::IpCheck,
            90 => Self::Secondaries,
            100 => Self::Activated,
            110 => Self::Deactivating,
            120 => Self::Failed,
            _ => Self::Unknown,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::Unmanaged => "unmanaged",
            Self::Unavailable => "unavailable",
            Self::Disconnected => "disconnected",
            Self::Prepare => "prepare",
            Self::Config => "config",
            Self::NeedAuth => "need-auth",
            Self::IpConfig => "ip-config",
            Self::IpCheck => "ip-check",
            Self::Secondaries => "secondaries",
            Self::Activated => "activated",
            Self::Deactivating => "deactivating",
            Self::Failed => "failed",
        }
    }

    /// Everything between asking for a link and having one, `NeedAuth` included:
    /// `Network.qml:22` calls that `wifiConnecting`.
    pub fn connecting(&self) -> bool {
        matches!(
            self,
            Self::Prepare | Self::Config | Self::NeedAuth | Self::IpConfig | Self::IpCheck | Self::Secondaries
        )
    }
}

/// `NM_ACTIVE_CONNECTION_STATE`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ActiveState {
    #[default]
    Unknown,
    Activating,
    Activated,
    Deactivating,
    Deactivated,
}

impl ActiveState {
    pub fn from_u32(value: u32) -> Self {
        match value {
            1 => Self::Activating,
            2 => Self::Activated,
            3 => Self::Deactivating,
            4 => Self::Deactivated,
            _ => Self::Unknown,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::Activating => "activating",
            Self::Activated => "activated",
            Self::Deactivating => "deactivating",
            Self::Deactivated => "deactivated",
        }
    }

    /// Nothing further is coming for these two.
    pub fn settled(&self) -> bool {
        matches!(self, Self::Activated | Self::Deactivated)
    }
}

/// `NM_ACTIVE_CONNECTION_STATE_REASON`, the second argument of `StateChanged`. Only the
/// values a wifi connect can end on are named; the rest is the number, because a reason
/// this crate cannot explain is still worth putting in front of the user.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActivationReason {
    None,
    UserDisconnected,
    DeviceDisconnected,
    ConnectTimeout,
    NoSecrets,
    LoginFailed,
    DependencyFailed,
    Other(u32),
}

impl ActivationReason {
    pub fn from_u32(value: u32) -> Self {
        match value {
            1 => Self::None,
            2 => Self::UserDisconnected,
            3 => Self::DeviceDisconnected,
            6 => Self::ConnectTimeout,
            9 => Self::NoSecrets,
            10 => Self::LoginFailed,
            12 => Self::DependencyFailed,
            other => Self::Other(other),
        }
    }

    pub fn as_str(&self) -> Cow<'static, str> {
        match self {
            Self::None => "no reason given".into(),
            Self::UserDisconnected => "disconnected by the user".into(),
            Self::DeviceDisconnected => "the device disconnected".into(),
            Self::ConnectTimeout => "the network did not answer in time".into(),
            Self::NoSecrets => "the network needs a passphrase".into(),
            Self::LoginFailed => "the network did not accept that passphrase".into(),
            Self::DependencyFailed => "a connection it depends on failed".into(),
            Self::Other(value) => format!("NetworkManager reason {value}").into(),
        }
    }
}

/// `Network.qml:33`, verbatim: the five strings the shell already branches on.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum WifiStatus {
    Disabled,
    #[default]
    Disconnected,
    Connecting,
    Connected,
    Limited,
}

impl WifiStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Disabled => "disabled",
            Self::Disconnected => "disconnected",
            Self::Connecting => "connecting",
            Self::Connected => "connected",
            Self::Limited => "limited",
        }
    }

    /// The QML's own derivation at `:196-219`, off the enum instead of off nmcli's prose.
    pub fn derive(enabled: bool, state: DeviceState, connectivity: Connectivity) -> Self {
        if !enabled {
            return Self::Disabled;
        }
        match state {
            DeviceState::Unmanaged | DeviceState::Unavailable | DeviceState::Unknown => {
                Self::Disabled
            }
            DeviceState::Activated if connectivity.degraded() => Self::Limited,
            DeviceState::Activated => Self::Connected,
            state if state.connecting() => Self::Connecting,
            _ => Self::Disconnected,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_five_qml_status_strings_come_out_of_the_enum_pair() {
        let full = Connectivity::Full;
        assert_eq!(
            WifiStatus::derive(false, DeviceState::Activated, full),
            WifiStatus::Disabled
        );
        assert_eq!(
            WifiStatus::derive(true, DeviceState::Unavailable, full),
            WifiStatus::Disabled
        );
        assert_eq!(
            WifiStatus::derive(true, DeviceState::Disconnected, full),
            WifiStatus::Disconnected
        );
        assert_eq!(
            WifiStatus::derive(true, DeviceState::NeedAuth, full),
            WifiStatus::Connecting
        );
        assert_eq!(
            WifiStatus::derive(true, DeviceState::Activated, full),
            WifiStatus::Connected
        );
    }

    /// `Network.qml:208` only ever sees nmcli's word `limited`, so a captive portal
    /// reads as fully connected there. Both degrade here, and `Connectivity` still
    /// says which one it was.
    #[test]
    fn a_captive_portal_degrades_the_status_the_way_limited_does() {
        assert_eq!(
            WifiStatus::derive(true, DeviceState::Activated, Connectivity::Portal),
            WifiStatus::Limited
        );
        assert_eq!(
            WifiStatus::derive(true, DeviceState::Activated, Connectivity::Limited),
            WifiStatus::Limited
        );
        assert!(Connectivity::Portal.degraded());
        assert!(!Connectivity::Full.degraded());
    }

    /// The live values read off this seat while the job ran, so a renumbering upstream
    /// fails here rather than in the bar.
    #[test]
    fn the_values_this_seat_reported_map_to_the_names_they_mean() {
        assert_eq!(NmState::from_u32(70), NmState::ConnectedGlobal);
        assert_eq!(Connectivity::from_u32(4), Connectivity::Full);
        assert_eq!(DeviceType::from_u32(2), DeviceType::Wifi);
        assert_eq!(DeviceState::from_u32(100), DeviceState::Activated);
        assert_eq!(ActiveState::from_u32(2), ActiveState::Activated);
        assert_eq!(DeviceType::from_u32(32), DeviceType::Other(32));
    }

    /// 9 is the number this seat's journal carried under `no secrets: No agents were
    /// available for this request`, eight times over, while the shell reported every one
    /// of those attempts to the user as a success.
    #[test]
    fn the_reason_a_seat_with_no_secret_agent_fails_with_is_named() {
        assert_eq!(ActivationReason::from_u32(9), ActivationReason::NoSecrets);
        assert_eq!(ActivationReason::from_u32(10), ActivationReason::LoginFailed);
        assert_eq!(
            ActivationReason::NoSecrets.as_str(),
            "the network needs a passphrase"
        );
        assert_eq!(
            ActivationReason::from_u32(255),
            ActivationReason::Other(255)
        );
        assert_eq!(
            ActivationReason::Other(255).as_str(),
            "NetworkManager reason 255"
        );
    }

    /// Activating and Deactivating both have something still to come; waiting on either
    /// as if it were a verdict is what returned success from a failing connection.
    #[test]
    fn only_activated_and_deactivated_end_an_activation() {
        assert!(ActiveState::Activated.settled());
        assert!(ActiveState::Deactivated.settled());
        assert!(!ActiveState::Activating.settled());
        assert!(!ActiveState::Deactivating.settled());
        assert!(!ActiveState::Unknown.settled());
    }
}
