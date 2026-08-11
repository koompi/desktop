//! D10 battery, D11 charge threshold, D12 power profiles and the shell-wide poll
//! multiplier that every other crate's timers take their rate from.
//!
//! Two of the three exist as deltas only because Quickshell 0.2.1 ships no generic
//! D-Bus client, stated at `ChargeLimit.qml:11-15`, so the QML shells out to `busctl`
//! four properties at a time. Here they are ordinary proxies.
//!
//! Nothing in this crate changes the seat unless it is asked to in so many words:
//! `set_charge_threshold_enabled` and `set_profile` are the only writes.

mod battery;
mod profiles;
mod props;
mod proxy;
mod service;

pub use battery::{
    battery_object_path, parse_cycle_count, Battery, BatteryState, ChargeThreshold, WarningLevel,
};
pub use profiles::{Profile, Profiles};
pub use service::{PowerService, PowerState};

/// The `Config.options.battery` and `Config.options.power` knobs the QML reads, with
/// the same defaults: `Config.qml:352-354` and `PowerSaving.qml:22,39`. `full` at 101
/// is how the shell ships the full-battery notice off by default.
#[derive(Debug, Clone, PartialEq)]
pub struct PowerConfig {
    pub low_percent: f64,
    pub critical_percent: f64,
    pub full_percent: f64,
    /// `power.saveOnBattery`: off AC the shell does the same work half as often.
    pub save_on_battery: bool,
    /// False keeps power-profiles-daemon unopened, and unactivated, for a shell that
    /// does not show profiles. Reads then report it as `Unavailable`.
    pub power_profiles: bool,
}

impl Default for PowerConfig {
    fn default() -> Self {
        Self {
            low_percent: 20.0,
            critical_percent: 5.0,
            full_percent: 101.0,
            save_on_battery: true,
            power_profiles: true,
        }
    }
}
