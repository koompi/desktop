//! The connection profiles the write paths send, built as plain values so the wire form
//! can be asserted without a bus.
//!
//! `Network.qml` builds these by string-substituting into a shell command line, which is
//! why `:96` has to route a PSK through a `bash -c` and an environment variable to keep
//! it off the process table.

use std::collections::HashMap;

use koompi_service::{Error, Result};
use zvariant::{Array, OwnedValue, Str};

use crate::ap::{Security, Ssid};
use crate::props;
use crate::proxy::ConnectionSettings;

pub const WIRELESS: &str = "802-11-wireless";
pub const WIRELESS_SECURITY: &str = "802-11-wireless-security";
pub const CONNECTION: &str = "connection";

fn text(value: impl Into<String>) -> OwnedValue {
    OwnedValue::from(Str::from(value.into()))
}

fn bytes(value: &[u8]) -> Result<OwnedValue> {
    OwnedValue::try_from(Array::from(value.to_vec()))
        .map_err(|error| Error::Protocol(format!("ssid: {error}")))
}

/// The key management an access point's own advertisement asks for. WPA3-only networks
/// need `sae`; a transition-mode network advertises PSK too and takes `wpa-psk`.
pub fn key_mgmt(security: Security) -> Option<&'static str> {
    if security.enterprise() {
        return Some("wpa-eap");
    }
    if security.owe() || security.owe_transition() {
        return Some("owe");
    }
    if security.wpa2() || security.wpa1() {
        return Some("wpa-psk");
    }
    if security.wpa3() {
        return Some("sae");
    }
    if security.wep() {
        return Some("none");
    }
    None
}

/// What `nmcli dev wifi connect <ssid>` at `Network.qml:76` builds before handing it to
/// `AddAndActivateConnection`. NetworkManager fills in the UUID.
///
/// A `None` passphrase leaves the security setting out entirely, which sends NM to a
/// secret agent. A seat running this shell has no agent, so that is a refusal, not a
/// prompt: `NetworkService::connect_to` reuses a saved profile where there is one and
/// otherwise reports the refusal so the consumer can ask for the passphrase itself.
pub fn wifi_profile(
    ssid: &Ssid,
    security: Security,
    passphrase: Option<&str>,
) -> Result<ConnectionSettings> {
    let mut profile = ConnectionSettings::new();

    profile.insert(
        CONNECTION.to_owned(),
        HashMap::from([
            ("id".to_owned(), text(ssid.to_lossy().into_owned())),
            ("type".to_owned(), text(WIRELESS)),
        ]),
    );

    profile.insert(
        WIRELESS.to_owned(),
        HashMap::from([
            ("ssid".to_owned(), bytes(ssid.as_bytes())?),
            ("mode".to_owned(), text("infrastructure")),
        ]),
    );

    if let (Some(passphrase), Some(key_mgmt)) = (passphrase, key_mgmt(security)) {
        profile.insert(
            WIRELESS_SECURITY.to_owned(),
            HashMap::from([
                ("key-mgmt".to_owned(), text(key_mgmt)),
                ("psk".to_owned(), text(passphrase)),
            ]),
        );
    }

    Ok(profile)
}

/// The SSID a saved profile is for, as bytes. Matching on the profile's `id` instead
/// would miss every network renamed in another tool and collide across the two profiles
/// a byte-identical name can produce.
pub fn profile_ssid(saved: &ConnectionSettings) -> Option<Ssid> {
    props::bytes(saved.get(WIRELESS)?, "ssid").map(Ssid::new)
}

/// When NetworkManager last brought this profile up, which is 0 for one it never has.
/// Duplicates for a single SSID are ordinary - this seat carries eleven for one network -
/// so the one that has worked before is the one to reuse.
pub fn profile_last_used(saved: &ConnectionSettings) -> u64 {
    saved
        .get(CONNECTION)
        .and_then(|keys| keys.get("timestamp"))
        .and_then(|value| value.downcast_ref::<u64>().ok())
        .unwrap_or(0)
}

/// `Network.qml:96`, `nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"`: read the
/// saved profile, replace one key, write it back. The key management already on the
/// profile is kept, because the saved profile knows what the network wanted and a
/// passphrase change is not a change of mode.
pub fn profile_with_psk(saved: &ConnectionSettings, passphrase: &str) -> Result<ConnectionSettings> {
    let mut updated = ConnectionSettings::new();
    for (setting, keys) in saved {
        let mut copied = HashMap::new();
        for (key, value) in keys {
            let cloned = value
                .try_clone()
                .map_err(|error| Error::Protocol(format!("{setting}.{key}: {error}")))?;
            copied.insert(key.clone(), cloned);
        }
        updated.insert(setting.clone(), copied);
    }

    updated
        .entry(WIRELESS_SECURITY.to_owned())
        .or_default()
        .insert("psk".to_owned(), text(passphrase));

    Ok(updated)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ap::{SEC_KEY_MGMT_802_1X, SEC_KEY_MGMT_PSK, SEC_KEY_MGMT_SAE};

    fn string_at(profile: &ConnectionSettings, setting: &str, key: &str) -> String {
        profile
            .get(setting)
            .and_then(|keys| keys.get(key))
            .and_then(|value| value.downcast_ref::<String>().ok())
            .unwrap_or_else(|| panic!("{setting}.{key} missing"))
    }

    fn ssid_bytes(profile: &ConnectionSettings) -> Vec<u8> {
        let value = profile.get(WIRELESS).unwrap().get("ssid").unwrap();
        let zvariant::Value::Array(array) = &**value else {
            panic!("ssid is not an array");
        };
        array
            .iter()
            .map(|value| match value {
                zvariant::Value::U8(byte) => *byte,
                other => panic!("ssid holds {other:?}"),
            })
            .collect()
    }

    /// The live network's flags, `Flags 1 WpaFlags 332 RsnFlags 332`. Never sent.
    fn toursanak() -> Security {
        Security {
            flags: 1,
            wpa: 332,
            rsn: 332,
        }
    }

    #[test]
    fn the_connect_profile_carries_the_ssid_as_bytes_not_as_a_string() {
        let ssid = Ssid::new(b"Toursanak".to_vec());
        let profile = wifi_profile(&ssid, toursanak(), Some("hunter2")).unwrap();

        assert_eq!(string_at(&profile, CONNECTION, "id"), "Toursanak");
        assert_eq!(string_at(&profile, CONNECTION, "type"), WIRELESS);
        assert_eq!(ssid_bytes(&profile), b"Toursanak".to_vec());
        assert_eq!(string_at(&profile, WIRELESS, "mode"), "infrastructure");
        assert_eq!(
            string_at(&profile, WIRELESS_SECURITY, "key-mgmt"),
            "wpa-psk"
        );
        assert_eq!(string_at(&profile, WIRELESS_SECURITY, "psk"), "hunter2");
    }

    /// An SSID that is not UTF-8 must still reach the wire byte for byte. The `id` is
    /// the only place the lossy form is allowed, because a profile name is text.
    #[test]
    fn a_non_utf8_ssid_is_sent_whole_and_only_its_label_is_lossy() {
        let raw = vec![b'K', 0xff, b'O'];
        let profile = wifi_profile(&Ssid::new(raw.clone()), toursanak(), None).unwrap();

        assert_eq!(ssid_bytes(&profile), raw);
        assert_eq!(string_at(&profile, CONNECTION, "id"), "K\u{fffd}O");
    }

    /// Which on an agentless seat is what NetworkManager refuses with `no-secrets`, and
    /// is why the connect path has to hear the refusal rather than assume a prompt.
    #[test]
    fn no_passphrase_leaves_the_security_setting_out() {
        let profile = wifi_profile(&Ssid::new(b"B28".to_vec()), toursanak(), None).unwrap();
        assert!(!profile.contains_key(WIRELESS_SECURITY));
    }

    /// The saved profile is found by these bytes. An SSID the router broadcasts as
    /// non-UTF-8 renders identically to every other one that also fails to decode, so a
    /// match on the label would hand back somebody else's network.
    #[test]
    fn a_saved_profile_is_matched_on_the_ssid_bytes_not_on_its_label() {
        let raw = vec![b'K', 0xff, b'O'];
        let saved = wifi_profile(&Ssid::new(raw.clone()), toursanak(), Some("hunter2")).unwrap();

        assert_eq!(profile_ssid(&saved), Some(Ssid::new(raw)));
        assert_ne!(profile_ssid(&saved), Some(Ssid::new(vec![b'K', 0xfe, b'O'])));
    }

    /// Eleven profiles for one SSID is what this seat actually holds. Ten never
    /// connected; reusing one of those asks for a passphrase that is already on disk in
    /// the eleventh.
    #[test]
    fn a_profile_that_has_never_connected_sorts_below_one_that_has() {
        let mut fresh = wifi_profile(&Ssid::new(b"Kraya Angkor".to_vec()), toursanak(), None)
            .unwrap();
        assert_eq!(profile_last_used(&fresh), 0);

        fresh
            .get_mut(CONNECTION)
            .unwrap()
            .insert("timestamp".to_owned(), OwnedValue::from(1786527965u64));
        assert_eq!(profile_last_used(&fresh), 1786527965);
    }

    #[test]
    fn a_profile_that_is_not_wireless_has_no_ssid_to_match() {
        let mut wired = ConnectionSettings::new();
        wired.insert(
            CONNECTION.to_owned(),
            HashMap::from([("type".to_owned(), text("802-3-ethernet"))]),
        );
        assert_eq!(profile_ssid(&wired), None);
    }

    #[test]
    fn an_open_network_gets_no_security_setting_even_with_a_passphrase() {
        let profile = wifi_profile(
            &Ssid::new(b"Airport Free".to_vec()),
            Security::default(),
            Some("ignored"),
        )
        .unwrap();
        assert!(!profile.contains_key(WIRELESS_SECURITY));
    }

    #[test]
    fn key_management_follows_what_the_access_point_advertised() {
        assert_eq!(key_mgmt(toursanak()), Some("wpa-psk"));
        assert_eq!(
            key_mgmt(Security {
                flags: 1,
                wpa: 0,
                rsn: SEC_KEY_MGMT_SAE,
            }),
            Some("sae")
        );
        assert_eq!(
            key_mgmt(Security {
                flags: 1,
                wpa: 0,
                rsn: SEC_KEY_MGMT_PSK | SEC_KEY_MGMT_SAE,
            }),
            Some("wpa-psk")
        );
        assert_eq!(
            key_mgmt(Security {
                flags: 1,
                wpa: 0,
                rsn: SEC_KEY_MGMT_802_1X,
            }),
            Some("wpa-eap")
        );
        assert_eq!(key_mgmt(Security::default()), None);
    }

    /// Never fired against this seat. What is checked is that the rewrite touches one
    /// key and carries every other setting through unchanged, because `Update` replaces
    /// the whole profile and anything dropped here is deleted from the saved network.
    #[test]
    fn a_psk_change_replaces_one_key_and_preserves_the_rest_of_the_profile() {
        let mut saved = ConnectionSettings::new();
        saved.insert(
            CONNECTION.to_owned(),
            HashMap::from([
                ("id".to_owned(), text("Toursanak")),
                (
                    "uuid".to_owned(),
                    text("374d5e77-0c73-4c75-aeeb-511e537593bd"),
                ),
                ("type".to_owned(), text(WIRELESS)),
            ]),
        );
        saved.insert(
            WIRELESS_SECURITY.to_owned(),
            HashMap::from([
                ("key-mgmt".to_owned(), text("wpa-psk")),
                ("auth-alg".to_owned(), text("open")),
            ]),
        );
        saved.insert(
            "ipv4".to_owned(),
            HashMap::from([("method".to_owned(), text("auto"))]),
        );

        let updated = profile_with_psk(&saved, "a new passphrase").unwrap();

        assert_eq!(string_at(&updated, WIRELESS_SECURITY, "psk"), "a new passphrase");
        assert_eq!(
            string_at(&updated, WIRELESS_SECURITY, "key-mgmt"),
            "wpa-psk"
        );
        assert_eq!(string_at(&updated, WIRELESS_SECURITY, "auth-alg"), "open");
        assert_eq!(
            string_at(&updated, CONNECTION, "uuid"),
            "374d5e77-0c73-4c75-aeeb-511e537593bd"
        );
        assert_eq!(string_at(&updated, "ipv4", "method"), "auto");
        assert_eq!(updated.len(), 3);

        assert!(
            !saved
                .get(WIRELESS_SECURITY)
                .unwrap()
                .contains_key("psk"),
            "the saved profile handed in must not be mutated"
        );
    }

    #[test]
    fn a_profile_with_no_security_setting_yet_gains_one() {
        let saved = ConnectionSettings::from([(
            CONNECTION.to_owned(),
            HashMap::from([("id".to_owned(), text("Open"))]),
        )]);
        let updated = profile_with_psk(&saved, "s").unwrap();
        assert_eq!(string_at(&updated, WIRELESS_SECURITY, "psk"), "s");
    }
}
