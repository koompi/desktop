//! D10 and D11: what `Battery.qml:12-34` publishes, plus the sysfs cycle count it
//! reads at `Battery.qml:55-68` and the charge thresholds `ChargeLimit.qml` shells
//! `busctl` for.

use koompi_service::{Error, Result};
use zvariant::OwnedObjectPath;

use crate::props::{self, Props};
use crate::PowerConfig;

pub const DEVICES_PREFIX: &str = "/org/freedesktop/UPower/devices/";

const KIND_BATTERY: u32 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BatteryState {
    Unknown,
    Charging,
    Discharging,
    Empty,
    FullyCharged,
    PendingCharge,
    PendingDischarge,
}

impl BatteryState {
    fn from_upower(value: u32) -> Self {
        match value {
            1 => Self::Charging,
            2 => Self::Discharging,
            3 => Self::Empty,
            4 => Self::FullyCharged,
            5 => Self::PendingCharge,
            6 => Self::PendingDischarge,
            _ => Self::Unknown,
        }
    }

    /// The spelling `upower -i` prints, so the two can be diffed literally.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::Charging => "charging",
            Self::Discharging => "discharging",
            Self::Empty => "empty",
            Self::FullyCharged => "fully-charged",
            Self::PendingCharge => "pending-charge",
            Self::PendingDischarge => "pending-discharge",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WarningLevel {
    Unknown,
    None,
    Discharging,
    Low,
    Critical,
    Action,
}

impl WarningLevel {
    fn from_upower(value: u32) -> Self {
        match value {
            1 => Self::None,
            2 => Self::Discharging,
            3 => Self::Low,
            4 => Self::Critical,
            5 => Self::Action,
            _ => Self::Unknown,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Unknown => "unknown",
            Self::None => "none",
            Self::Discharging => "discharging",
            Self::Low => "low",
            Self::Critical => "critical",
            Self::Action => "action",
        }
    }
}

/// Stop charging at `end`, resume at `start`. `supported` false covers both a pack
/// without the feature and a UPower below 1.90, which has no such properties at all
/// and is the `lines.length < 4` branch at `ChargeLimit.qml:65`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ChargeThreshold {
    pub supported: bool,
    pub enabled: bool,
    pub start: u32,
    pub end: u32,
}

impl ChargeThreshold {
    fn from_props(props: &Props) -> Self {
        Self {
            supported: props::boolean(props, "ChargeThresholdSupported").unwrap_or(false),
            enabled: props::boolean(props, "ChargeThresholdEnabled").unwrap_or(false),
            start: props::u32_at(props, "ChargeStartThreshold").unwrap_or(0),
            end: props::u32_at(props, "ChargeEndThreshold").unwrap_or(0),
        }
    }
}

/// `percentage`, `health` and the energy figures are in UPower's own units: percent
/// and watt-hours. `Battery.qml:16` normalises percentage to 0..1 for its bindings;
/// that is a presentation choice and does not belong this far down.
#[derive(Debug, Clone, PartialEq)]
pub struct Battery {
    pub path: String,
    pub native_path: String,
    pub present: bool,
    pub state: BatteryState,
    pub charging: bool,
    pub percentage: f64,
    pub low: bool,
    pub critical: bool,
    pub full: bool,
    pub energy: f64,
    pub energy_full: f64,
    pub energy_full_design: f64,
    pub energy_rate: f64,
    pub time_to_empty: i64,
    pub time_to_full: i64,
    pub health: Option<f64>,
    pub cycle_count: Option<u32>,
    pub warning: WarningLevel,
    pub icon_name: String,
    pub threshold: ChargeThreshold,
}

impl Battery {
    pub(crate) fn from_props(path: &str, props: &Props, config: &PowerConfig) -> Self {
        let state = BatteryState::from_upower(props::u32_at(props, "State").unwrap_or(0));
        let percentage = props::f64_at(props, "Percentage").unwrap_or(0.0);
        let native_path = props::text(props, "NativePath").unwrap_or_default();
        let present = props::boolean(props, "IsPresent").unwrap_or(false);

        Self {
            path: path.to_owned(),
            present,
            state,
            charging: state == BatteryState::Charging,
            percentage,
            low: present && percentage <= config.low_percent,
            critical: present && percentage <= config.critical_percent,
            full: present && percentage >= config.full_percent,
            energy: props::f64_at(props, "Energy").unwrap_or(0.0),
            energy_full: props::f64_at(props, "EnergyFull").unwrap_or(0.0),
            energy_full_design: props::f64_at(props, "EnergyFullDesign").unwrap_or(0.0),
            energy_rate: props::f64_at(props, "EnergyRate").unwrap_or(0.0),
            time_to_empty: props::i64_at(props, "TimeToEmpty").unwrap_or(0),
            time_to_full: props::i64_at(props, "TimeToFull").unwrap_or(0),
            health: health_of(props),
            cycle_count: cycle_count_of(&native_path, props),
            warning: WarningLevel::from_upower(props::u32_at(props, "WarningLevel").unwrap_or(0)),
            icon_name: props::text(props, "IconName").unwrap_or_default(),
            threshold: ChargeThreshold::from_props(props),
            native_path,
        }
    }
}

/// UPower's `Capacity`, energy-full over energy-full-design. A pack that reports zero
/// is reporting "I do not know", not a dead pack, so it reads as absent.
fn health_of(props: &Props) -> Option<f64> {
    props::f64_at(props, "Capacity").filter(|health| *health > 0.0)
}

/// sysfs first, because it is the source `Battery.qml:53` reads and the only one on a
/// UPower below 1.91. `ChargeCycles` is the newer path and carries -1 for unknown.
fn cycle_count_of(native_path: &str, props: &Props) -> Option<u32> {
    read_cycle_count(native_path).or_else(|| {
        props::i32_at(props, "ChargeCycles")
            .filter(|cycles| *cycles > 0)
            .map(|cycles| cycles as u32)
    })
}

fn read_cycle_count(native_path: &str) -> Option<u32> {
    if native_path.is_empty() {
        return None;
    }
    let path = format!("/sys/class/power_supply/{native_path}/cycle_count");
    parse_cycle_count(&std::fs::read_to_string(path).ok()?)
}

/// Absent, unreadable or a pack that answers "0" all mean the same thing to a
/// consumer: there is no cycle count to draw.
pub fn parse_cycle_count(text: &str) -> Option<u32> {
    text.trim().parse::<u32>().ok().filter(|count| *count > 0)
}

pub(crate) fn is_laptop_battery(props: &Props) -> bool {
    props::u32_at(props, "Type") == Some(KIND_BATTERY)
        && props::boolean(props, "PowerSupply").unwrap_or(false)
}

/// The port of `ChargeLimit.qml:21-30`, which interpolates `nativePath` straight into
/// the path. UPower mangles it first: on this seat `ucsi-source-psy-USBC000:001`
/// answers at `line_power_ucsi_source_psy_USBC000o001`, so `-` becomes `_` and `:`
/// becomes `o`. Prefer matching an enumerated device by `NativePath`; this is for the
/// case where there is nothing to enumerate.
pub fn battery_object_path(native_path: &str) -> Result<OwnedObjectPath> {
    if native_path.is_empty() {
        return Err(Error::Unavailable("battery".into()));
    }
    let path = format!("{DEVICES_PREFIX}battery_{}", mangle(native_path));
    OwnedObjectPath::try_from(path.clone()).map_err(|_| {
        Error::Protocol(format!(
            "{native_path} does not name a d-bus object: {path}"
        ))
    })
}

fn mangle(native_path: &str) -> String {
    let basename = native_path.rsplit('/').next().unwrap_or(native_path);
    basename
        .chars()
        .map(|c| match c {
            ':' => 'o',
            c if c.is_ascii_alphanumeric() || c == '_' => c,
            _ => '_',
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Both pairs read off this seat's UPower with `busctl get-property NativePath`
    /// against every path `upower -e` lists.
    #[test]
    fn native_path_derives_the_object_path_upower_actually_answers_at() {
        assert_eq!(
            battery_object_path("BAT0").unwrap().as_str(),
            "/org/freedesktop/UPower/devices/battery_BAT0"
        );
        assert_eq!(
            battery_object_path("ucsi-source-psy-USBC000:001")
                .unwrap()
                .as_str(),
            "/org/freedesktop/UPower/devices/battery_ucsi_source_psy_USBC000o001"
        );
    }

    /// The display device carries an empty native path, and `ChargeLimit.qml:40`
    /// bails on that rather than calling busctl with a truncated path.
    #[test]
    fn an_empty_native_path_is_unavailable_not_a_bad_object_path() {
        assert!(matches!(
            battery_object_path(""),
            Err(Error::Unavailable(_))
        ));
    }

    #[test]
    fn cycle_count_parses_this_battery_and_rejects_the_rest() {
        assert_eq!(parse_cycle_count("107\n"), Some(107));
        assert_eq!(parse_cycle_count(""), None);
        assert_eq!(parse_cycle_count("0\n"), None);
        assert_eq!(parse_cycle_count("unknown\n"), None);
    }

    #[test]
    fn state_and_warning_spell_themselves_the_way_upower_prints_them() {
        assert_eq!(BatteryState::from_upower(2).as_str(), "discharging");
        assert_eq!(BatteryState::from_upower(4).as_str(), "fully-charged");
        assert_eq!(BatteryState::from_upower(99).as_str(), "unknown");
        assert_eq!(WarningLevel::from_upower(1).as_str(), "none");
    }
}
