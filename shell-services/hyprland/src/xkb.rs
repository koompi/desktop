//! D03. Hyprland reports the active layout by description ("English (US)"); the code an
//! indicator draws ("us") only exists in the xkb rules list, as `HyprlandXkb.qml:35-74`
//! discovered.

use std::collections::HashMap;
use std::path::Path;

use serde::Deserialize;

use koompi_service::{Error, Result};

pub const BASE_LST: &str = "/usr/share/X11/xkb/rules/base.lst";

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Keyboard {
    pub name: String,
    pub layout_codes: Vec<String>,
    pub active_name: String,
    pub active_code: String,
}

#[derive(Debug, Clone, Default)]
pub struct LayoutIndex {
    by_description: HashMap<String, String>,
}

impl LayoutIndex {
    /// Reads the `! layout` and `! variant` sections. A variant line names its base layout
    /// with a trailing colon ("dvorak  gb: English (UK, Dvorak)"), which becomes the
    /// canonical `gb(dvorak)` rather than the `gb:dvorak` the QML regex left behind.
    pub fn parse(text: &str) -> Self {
        let mut by_description = HashMap::new();
        let mut section = "";

        for line in text.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Some(header) = trimmed.strip_prefix('!') {
                section = match header.trim() {
                    "layout" => "layout",
                    "variant" => "variant",
                    _ => "",
                };
                continue;
            }

            let Some((first, rest)) = trimmed.split_once(char::is_whitespace) else {
                continue;
            };
            let rest = rest.trim();

            match section {
                "layout" => {
                    by_description.insert(rest.to_string(), first.to_string());
                }
                "variant" => {
                    let Some((base, description)) = rest.split_once(char::is_whitespace) else {
                        continue;
                    };
                    let base = base.trim_end_matches(':');
                    by_description
                        .insert(description.trim().to_string(), format!("{base}({first})"));
                }
                _ => {}
            }
        }

        Self { by_description }
    }

    pub async fn load(path: impl AsRef<Path>) -> Result<Self> {
        let text = tokio::fs::read_to_string(path).await?;
        Ok(Self::parse(&text))
    }

    pub fn code_for(&self, description: &str) -> Option<&str> {
        self.by_description.get(description).map(String::as_str)
    }

    pub fn len(&self) -> usize {
        self.by_description.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_description.is_empty()
    }
}

#[derive(Debug, Deserialize)]
struct Devices {
    #[serde(default)]
    keyboards: Vec<DeviceKeyboard>,
}

#[derive(Debug, Deserialize)]
struct DeviceKeyboard {
    #[serde(default)]
    name: String,
    #[serde(default)]
    main: bool,
    #[serde(default)]
    layout: String,
    #[serde(default)]
    active_keymap: String,
}

/// The main keyboard out of `j/devices`, as `HyprlandXkb.qml:86-88` picks it.
pub fn keyboard_from_devices(json: &str) -> Result<Keyboard> {
    let devices: Devices =
        serde_json::from_str(json).map_err(|e| Error::Protocol(format!("j/devices: {e}")))?;
    let main = devices
        .keyboards
        .into_iter()
        .find(|k| k.main)
        .ok_or_else(|| Error::Protocol("j/devices: no main keyboard".into()))?;

    Ok(Keyboard {
        name: main.name,
        layout_codes: main
            .layout
            .split(',')
            .map(|c| c.trim().to_string())
            .filter(|c| !c.is_empty())
            .collect(),
        active_name: main.active_keymap,
        active_code: String::new(),
    })
}

/// `activelayout>>keyboard_name,Layout Description`. The description may contain commas of
/// its own, so only the first splits.
pub fn parse_activelayout(data: &str) -> Option<(&str, &str)> {
    data.split_once(',')
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASE: &str = include_str!("../tests/fixtures/base.lst");
    const DEVICES: &str = include_str!("../tests/fixtures/devices.json");

    #[test]
    fn maps_layout_descriptions_to_codes_from_the_captured_rules_list() {
        let index = LayoutIndex::parse(BASE);

        assert_eq!(index.code_for("English (US)"), Some("us"));
        assert_eq!(index.code_for("Khmer (Cambodia)"), Some("kh"));
        assert_eq!(index.code_for("French"), Some("fr"));
        assert_eq!(index.code_for("Nothing (Nowhere)"), None);
    }

    #[test]
    fn variant_descriptions_map_to_base_and_variant() {
        let index = LayoutIndex::parse(BASE);

        assert_eq!(index.code_for("English (UK, Dvorak)"), Some("gb(dvorak)"));
        assert_eq!(index.code_for("Arabic (AZERTY)"), Some("ara(azerty)"));
    }

    #[test]
    fn model_and_option_sections_are_not_indexed() {
        let index = LayoutIndex::parse(BASE);

        assert_eq!(index.code_for("Generic 86-key PC"), None);
        assert_eq!(index.code_for("Right Alt (while pressed)"), None);
        assert_eq!(index.len(), 14);
    }

    #[test]
    fn main_keyboard_and_its_layouts_come_out_of_captured_devices_json() {
        let keyboard = keyboard_from_devices(DEVICES).unwrap();

        assert_eq!(keyboard.name, "at-translated-set-2-keyboard");
        assert_eq!(keyboard.layout_codes, ["us", "kh"]);
        assert_eq!(keyboard.active_name, "English (US)");
        assert_eq!(
            LayoutIndex::parse(BASE).code_for(&keyboard.active_name),
            Some("us")
        );
    }

    #[test]
    fn activelayout_payload_splits_on_the_first_comma_only() {
        assert_eq!(
            parse_activelayout("at-translated-set-2-keyboard,Khmer (Cambodia)"),
            Some(("at-translated-set-2-keyboard", "Khmer (Cambodia)"))
        );
        assert_eq!(
            parse_activelayout("kbd,English (US, intl., with dead keys)"),
            Some(("kbd", "English (US, intl., with dead keys)"))
        );
        assert_eq!(parse_activelayout("nocomma"), None);
    }
}
