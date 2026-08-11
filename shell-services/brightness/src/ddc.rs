//! External panels, still through the `ddcutil` binary. `AUDIT.md` records `libddcutil`
//! as considered and rejected, so the port is of the parsing at `Brightness.qml:74-88`
//! and nothing else.

use std::time::Duration;

use koompi_service::{Error, Result};
use tokio::process::Command;

/// `ddcutil` talks to the panel over I2C and a detect across several buses is seconds,
/// not milliseconds. A monitor that never answers must not hold the service's start.
const DETECT_TIMEOUT: Duration = Duration::from_secs(20);
const CALL_TIMEOUT: Duration = Duration::from_secs(10);

/// VCP feature 0x10, luminance.
const LUMINANCE: &str = "10";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Monitor {
    pub connector: String,
    pub bus: u8,
}

pub async fn detect() -> Vec<Monitor> {
    match run(&["detect", "--brief"]).await {
        Ok(output) => parse_detect(&output),
        Err(_) => Vec::new(),
    }
}

pub async fn get_luminance(bus: u8) -> Result<(u32, u32)> {
    let output = run(&["-b", &bus.to_string(), "getvcp", LUMINANCE, "--brief"]).await?;
    parse_getvcp(&output).ok_or_else(|| Error::Protocol(format!("getvcp 10: {}", output.trim())))
}

pub async fn set_luminance(bus: u8, raw: u32) -> Result<()> {
    run(&[
        "-b",
        &bus.to_string(),
        "setvcp",
        LUMINANCE,
        &raw.to_string(),
    ])
    .await?;
    Ok(())
}

async fn run(args: &[&str]) -> Result<String> {
    let output = tokio::time::timeout(
        if args.first() == Some(&"detect") {
            DETECT_TIMEOUT
        } else {
            CALL_TIMEOUT
        },
        Command::new("ddcutil").args(args).output(),
    )
    .await
    .map_err(|_| Error::Unavailable("ddcutil".into()))?
    .map_err(|_| Error::Unavailable("ddcutil".into()))?;

    if !output.status.success() {
        return Err(Error::Protocol(format!(
            "ddcutil {}: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

/// `Brightness.qml:77-84` keys off the `Display ` prefix, which is what keeps the
/// `Invalid display` blocks - the internal eDP panel among them - out of the list.
fn parse_detect(output: &str) -> Vec<Monitor> {
    output
        .split("\n\n")
        .filter(|block| block.trim_start().starts_with("Display "))
        .filter_map(|block| {
            let mut connector = None;
            let mut bus = None;
            for line in block.lines().map(str::trim) {
                if let Some(value) = line.strip_prefix("DRM connector:") {
                    connector = crate::panel::drm_connector(value.trim());
                } else if let Some(value) = line.strip_prefix("I2C bus:") {
                    bus = value.trim().strip_prefix("/dev/i2c-")?.parse().ok();
                }
            }
            Some(Monitor {
                connector: connector?,
                bus: bus?,
            })
        })
        .collect()
}

/// `VCP 10 C 46 100`: feature, type, current, max. `Brightness.qml:137` reads the
/// fourth and fifth fields, which is also what the `brightnessctl` branch produced.
fn parse_getvcp(output: &str) -> Option<(u32, u32)> {
    let fields: Vec<&str> = output.split_whitespace().collect();
    match fields.as_slice() {
        [_, _, _, current, max, ..] => Some((current.parse().ok()?, max.parse().ok()?)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The first block is this machine's real `ddcutil detect --brief`, captured on
    /// 2026-08-10. The two `Display` blocks follow ddcutil's documented layout: there is
    /// no external monitor on this seat to capture one from.
    const DETECT: &str = "Invalid display
   I2C bus:          /dev/i2c-11
   DRM connector:    card0-eDP-1
   drm_connector_id: 393
   Monitor:          BOE::

Display 1
   I2C bus:          /dev/i2c-4
   DRM connector:    card0-DP-1
   drm_connector_id: 105
   Monitor:          DEL:DELL U2720Q:CN0ABCD

Display 2
   I2C bus:          /dev/i2c-7
   DRM connector:    card0-HDMI-A-1
   drm_connector_id: 112
   Monitor:          GSM:LG HDR 4K:0x01010101
";

    #[test]
    fn detect_takes_the_connector_and_the_bus_off_every_display_block() {
        let monitors = parse_detect(DETECT);

        assert_eq!(
            monitors,
            vec![
                Monitor {
                    connector: "DP-1".into(),
                    bus: 4
                },
                Monitor {
                    connector: "HDMI-A-1".into(),
                    bus: 7
                },
            ]
        );
    }

    /// The internal panel answers `detect` and cannot be driven over DDC. Taking it
    /// would put the crate's own logind panel on the list twice, once unwritable.
    #[test]
    fn an_invalid_display_is_not_a_monitor() {
        let internal_only = DETECT.split("\n\n").next().unwrap();

        assert!(parse_detect(internal_only).is_empty());
    }

    #[test]
    fn a_seat_with_no_external_monitor_detects_nothing() {
        assert!(parse_detect("").is_empty());
        assert!(parse_detect("Display 1\n   Monitor: no bus line\n").is_empty());
    }

    #[test]
    fn getvcp_reads_the_current_and_the_max_out_of_the_brief_line() {
        assert_eq!(parse_getvcp("VCP 10 C 46 100\n"), Some((46, 100)));
        assert_eq!(parse_getvcp("VCP 10 C 0 255\n"), Some((0, 255)));
        assert_eq!(parse_getvcp("VCP 10 ERR\n"), None);
        assert_eq!(parse_getvcp(""), None);
    }
}
