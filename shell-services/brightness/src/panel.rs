//! The value arithmetic, kept apart from anything that touches a device so the two
//! rounding rules `Brightness.qml` uses can be checked without a panel.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Backend {
    /// `org.freedesktop.login1.Session.SetBrightness`, which is D15's whole claim: the
    /// udev rule and the root requirement go away.
    Logind,
    Ddc,
}

impl Backend {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Logind => "logind",
            Self::Ddc => "ddc",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Panel {
    /// The sysfs device name for a logind panel, the DRM connector for a DDC one.
    pub id: String,
    /// `eDP-1`, `DP-1`. What `Quickshell.screens` calls the same output.
    pub connector: Option<String>,
    pub backend: Backend,
    pub raw: u32,
    pub raw_max: u32,
    /// `/dev/i2c-N`, DDC panels only.
    pub bus: Option<u8>,
}

impl Panel {
    pub fn fraction(&self) -> f64 {
        fraction(self.raw, self.raw_max)
    }

    pub fn percent(&self) -> f64 {
        self.fraction() * 100.0
    }
}

/// `Brightness.qml:138`.
pub fn fraction(raw: u32, raw_max: u32) -> f64 {
    if raw_max == 0 {
        return 0.0;
    }
    f64::from(raw) / f64::from(raw_max)
}

/// `Brightness.qml:162-165`. The percent step is not a rounding artefact to clean up: it
/// is what `brightnessctl s N%` did, and reproducing it keeps the same 100 stops the
/// shell's slider has always had. The floor below is the same line's refusal to send 0.
pub fn logind_raw(value: f64, raw_max: u32) -> u32 {
    let percent = (value.clamp(0.0, 1.0) * 100.0).floor() as u64;
    if percent == 0 {
        return 1;
    }
    let raw = percent * u64::from(raw_max) / 100;
    (raw as u32).max(1)
}

/// `Brightness.qml:159`. DDC panels report a small max, usually 100, so the QML scales
/// the fraction straight onto it rather than through a percent.
pub fn ddc_raw(value: f64, raw_max: u32) -> u32 {
    let raw = (value.clamp(0.0, 1.0) * f64::from(raw_max)).floor() as u32;
    raw.max(1)
}

/// `Brightness.qml:103`. The anti-flashbang multiplier arrives from outside this crate;
/// all that lives here is the clamp.
pub fn multiplied(brightness: f64, multiplier: f64) -> f64 {
    (brightness * multiplier).clamp(0.0, 1.0)
}

/// `card0-eDP-1` is what both `/sys/class/backlight/*/device` and `ddcutil detect`
/// name the output; `Quickshell.screens` calls it `eDP-1`.
pub fn drm_connector(card_connector: &str) -> Option<String> {
    let (card, connector) = card_connector.split_once('-')?;
    card.starts_with("card").then(|| connector.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// This seat: 80291 of 174545 on `intel_backlight`.
    #[test]
    fn the_raw_reading_normalises_the_way_the_qml_read_it() {
        assert!((fraction(80291, 174545) - 0.460_001_7).abs() < 1e-6);
        assert_eq!(fraction(0, 174545), 0.0);
        assert_eq!(fraction(174545, 174545), 1.0);
        // A panel that has not been read yet must not divide by its max.
        assert_eq!(fraction(0, 0), 0.0);
    }

    /// `Brightness.qml:164` sends the literal `1` rather than `0%` so the panel never
    /// goes fully black. A laptop with no external monitor cannot tell a dark panel
    /// from a hang.
    #[test]
    fn zero_becomes_one_raw_and_never_zero() {
        assert_eq!(logind_raw(0.0, 174545), 1);
        assert_eq!(logind_raw(-1.0, 174545), 1);
        // Anything under one percent floors to zero percent and hits the same floor.
        assert_eq!(logind_raw(0.009, 174545), 1);
        assert_eq!(ddc_raw(0.0, 100), 1);
        assert_eq!(ddc_raw(0.004, 100), 1);
    }

    #[test]
    fn percent_to_raw_floors_to_whole_percent_the_way_brightnessctl_did() {
        // 46% of this panel, which is where it sits now.
        assert_eq!(logind_raw(0.46, 174545), 80290);
        // 45.9% is still 45%, not 46%: the QML floors before it formats.
        assert_eq!(logind_raw(0.459, 174545), 78545);
        assert_eq!(logind_raw(0.01, 174545), 1745);
        assert_eq!(logind_raw(1.0, 174545), 174545);
        assert_eq!(logind_raw(2.0, 174545), 174545);
    }

    /// A panel whose max is under 100 would round every low percent to zero raw, which
    /// is the one case the percent floor alone does not cover.
    #[test]
    fn a_small_max_still_never_reaches_zero() {
        assert_eq!(logind_raw(0.05, 10), 1);
        assert_eq!(logind_raw(0.5, 10), 5);
    }

    #[test]
    fn the_ddc_path_scales_onto_the_reported_max_rather_than_a_percent() {
        assert_eq!(ddc_raw(0.46, 100), 46);
        assert_eq!(ddc_raw(0.469, 100), 46);
        assert_eq!(ddc_raw(1.0, 100), 100);
        assert_eq!(ddc_raw(0.5, 255), 127);
    }

    #[test]
    fn the_multiplier_is_clamped_to_the_unit_range() {
        assert_eq!(multiplied(0.5, 1.0), 0.5);
        assert_eq!(multiplied(0.5, 0.5), 0.25);
        assert_eq!(multiplied(0.8, 2.23), 1.0);
        assert_eq!(multiplied(0.5, -1.0), 0.0);
    }

    #[test]
    fn the_connector_drops_the_card_prefix_both_sysfs_and_ddcutil_carry() {
        assert_eq!(drm_connector("card0-eDP-1").as_deref(), Some("eDP-1"));
        assert_eq!(drm_connector("card1-DP-2").as_deref(), Some("DP-2"));
        assert_eq!(drm_connector("eDP-1"), None);
    }
}
