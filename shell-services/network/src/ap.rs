//! One access point, and the two things about it the QML gets wrong for free by going
//! through `nmcli`: the SSID is bytes, and the security label is three bitfields.

use std::borrow::Cow;
use std::fmt;

use crate::props::{self, Props};

/// `NM_802_11_AP_FLAGS`.
pub const AP_FLAG_PRIVACY: u32 = 0x1;
pub const AP_FLAG_WPS: u32 = 0x2;

/// `NM_802_11_AP_SEC_FLAGS`.
pub const SEC_KEY_MGMT_PSK: u32 = 0x100;
pub const SEC_KEY_MGMT_802_1X: u32 = 0x200;
pub const SEC_KEY_MGMT_SAE: u32 = 0x400;
pub const SEC_KEY_MGMT_OWE: u32 = 0x800;
pub const SEC_KEY_MGMT_OWE_TM: u32 = 0x1000;
pub const SEC_KEY_MGMT_EAP_SUITE_B_192: u32 = 0x2000;

/// An SSID as it arrives: up to 32 arbitrary octets. It is not text, it is not
/// NUL-terminated, and nothing in 802.11 says it is UTF-8.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default)]
pub struct Ssid(Vec<u8>);

impl Ssid {
    pub fn new(bytes: impl Into<Vec<u8>>) -> Self {
        Self(bytes.into())
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }

    /// A zero-length SSID is a hidden network, not an empty name.
    /// `Network.qml:288` drops these; the decision belongs to the consumer.
    pub fn is_hidden(&self) -> bool {
        self.0.is_empty()
    }

    /// Lossy on purpose. A byte sequence that is not UTF-8 still has to be drawn, and
    /// U+FFFD is what every other decoder in this stack would put there.
    pub fn to_lossy(&self) -> Cow<'_, str> {
        String::from_utf8_lossy(&self.0)
    }

    pub fn is_utf8(&self) -> bool {
        std::str::from_utf8(&self.0).is_ok()
    }
}

impl fmt::Display for Ssid {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.to_lossy())
    }
}

/// The `Flags` / `WpaFlags` / `RsnFlags` triple, kept whole. `Network.qml:286` takes
/// nmcli's rendering of it and can never ask a further question of it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Security {
    pub flags: u32,
    pub wpa: u32,
    pub rsn: u32,
}

impl Security {
    pub fn privacy(&self) -> bool {
        self.flags & AP_FLAG_PRIVACY != 0
    }

    pub fn wps(&self) -> bool {
        self.flags & AP_FLAG_WPS != 0
    }

    /// Privacy claimed with neither WPA nor RSN advertised leaves only WEP.
    pub fn wep(&self) -> bool {
        self.privacy() && self.wpa == 0 && self.rsn == 0
    }

    pub fn wpa1(&self) -> bool {
        self.wpa != 0
    }

    pub fn wpa2(&self) -> bool {
        self.rsn & (SEC_KEY_MGMT_PSK | SEC_KEY_MGMT_802_1X) != 0
    }

    pub fn wpa3(&self) -> bool {
        self.rsn & SEC_KEY_MGMT_SAE != 0
    }

    pub fn owe(&self) -> bool {
        self.rsn & SEC_KEY_MGMT_OWE != 0
    }

    pub fn owe_transition(&self) -> bool {
        self.rsn & SEC_KEY_MGMT_OWE_TM != 0
    }

    /// EAP. A PSK prompt is the wrong dialog for these.
    pub fn enterprise(&self) -> bool {
        (self.wpa | self.rsn) & SEC_KEY_MGMT_802_1X != 0
    }

    pub fn suite_b_192(&self) -> bool {
        (self.wpa | self.rsn) & SEC_KEY_MGMT_EAP_SUITE_B_192 != 0
    }

    pub fn open(&self) -> bool {
        !self.privacy() && self.wpa == 0 && self.rsn == 0
    }

    /// A pre-shared key is what the connect path can actually ask the user for.
    pub fn wants_psk(&self) -> bool {
        (self.wpa | self.rsn) & (SEC_KEY_MGMT_PSK | SEC_KEY_MGMT_SAE) != 0
    }

    /// nmcli's `SECURITY` column, token for token and in its order, so the list this
    /// crate publishes diffs clean against `nmcli -g ...,SECURITY d w`.
    pub fn label(&self) -> String {
        let mut tokens: Vec<&str> = Vec::new();
        if self.wep() {
            tokens.push("WEP");
        }
        if self.wpa1() {
            tokens.push("WPA1");
        }
        if self.wpa2() {
            tokens.push("WPA2");
        }
        if self.wpa3() {
            tokens.push("WPA3");
        }
        if self.owe() {
            tokens.push("OWE");
        }
        if self.owe_transition() {
            tokens.push("OWE-TM");
        }
        if self.enterprise() {
            tokens.push("802.1X");
        }
        if self.suite_b_192() {
            tokens.push("WPA-EAP-SUITE-B-192");
        }
        tokens.join(" ")
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct AccessPoint {
    pub path: String,
    pub ssid: Ssid,
    /// 0-100, nmcli's `SIGNAL`.
    pub strength: u8,
    /// MHz, nmcli's `FREQ`.
    pub frequency: u32,
    /// nmcli's `BSSID`.
    pub hw_address: String,
    pub max_bitrate: u32,
    pub bandwidth: u32,
    pub security: Security,
    /// Seconds of `CLOCK_BOOTTIME` when the AP was last seen in a scan, -1 if never.
    pub last_seen: i32,
    /// nmcli's `ACTIVE`: this is the AP the wireless device is associated with.
    pub active: bool,
}

impl AccessPoint {
    pub fn from_props(path: &str, props: &Props) -> Self {
        Self {
            path: path.to_owned(),
            ssid: Ssid::new(props::bytes(props, "Ssid").unwrap_or_default()),
            strength: props::u8_at(props, "Strength").unwrap_or(0),
            frequency: props::u32_at(props, "Frequency").unwrap_or(0),
            hw_address: props::text(props, "HwAddress").unwrap_or_default(),
            max_bitrate: props::u32_at(props, "MaxBitrate").unwrap_or(0),
            bandwidth: props::u32_at(props, "Bandwidth").unwrap_or(0),
            security: Security {
                flags: props::u32_at(props, "Flags").unwrap_or(0),
                wpa: props::u32_at(props, "WpaFlags").unwrap_or(0),
                rsn: props::u32_at(props, "RsnFlags").unwrap_or(0),
            },
            last_seen: props::i32_at(props, "LastSeen").unwrap_or(-1),
            active: false,
        }
    }

    /// 2, 5 or 6, the band nmcli prints in `nmcli -f FREQ` as a plain MHz number.
    pub fn band_ghz(&self) -> u8 {
        match self.frequency {
            0..=2999 => 2,
            3000..=5924 => 5,
            _ => 6,
        }
    }
}

/// `Network.qml:290-308`: one entry per SSID, the associated one winning over the
/// strongest, the strongest winning over the rest. The full per-BSSID list stays
/// available; this is only the view the QML publishes.
pub fn strongest_per_ssid(networks: &[AccessPoint]) -> Vec<AccessPoint> {
    let mut best: Vec<AccessPoint> = Vec::new();
    for ap in networks.iter().filter(|ap| !ap.ssid.is_hidden()) {
        match best.iter_mut().find(|kept| kept.ssid == ap.ssid) {
            None => best.push(ap.clone()),
            Some(kept) => {
                let wins = match (ap.active, kept.active) {
                    (true, false) => true,
                    (false, false) => ap.strength > kept.strength,
                    _ => false,
                };
                if wins {
                    *kept = ap.clone();
                }
            }
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Captured off this seat with
    /// `busctl --system call org.freedesktop.NetworkManager <ap> \
    ///  org.freedesktop.DBus.Properties GetAll s org.freedesktop.NetworkManager.AccessPoint`,
    /// paired with the `SECURITY` column `nmcli -g ...,SECURITY d w` printed for the
    /// same access point in the same minute.
    const CAPTURED: &[(&str, u32, u32, u32, &str)] = &[
        ("Toursanak", 1, 332, 332, "WPA1 WPA2"),
        ("B28", 1, 0, 332, "WPA2"),
        ("TP-Link_889C", 3, 0, 392, "WPA2"),
        ("Seavphovjivet", 3, 0, 392, "WPA2"),
        ("D28", 3, 0, 392, "WPA2"),
        ("Chhum Kim", 3, 392, 392, "WPA1 WPA2"),
        ("Physiothearapy", 3, 392, 392, "WPA1 WPA2"),
        ("D28_5G", 3, 0, 392, "WPA2"),
    ];

    #[test]
    fn every_access_point_in_range_gets_the_label_nmcli_gave_it() {
        for (ssid, flags, wpa, rsn, expected) in CAPTURED {
            let security = Security {
                flags: *flags,
                wpa: *wpa,
                rsn: *rsn,
            };
            assert_eq!(&security.label(), expected, "{ssid}");
            assert!(security.privacy(), "{ssid}");
            assert!(security.wants_psk(), "{ssid}");
            assert!(!security.enterprise(), "{ssid}");
        }
    }

    /// The bands no access point here broadcasts, so the mapping is pinned by
    /// construction rather than by whatever happens to be in range.
    #[test]
    fn the_labels_no_neighbour_broadcasts_still_come_out_the_way_nmcli_writes_them() {
        let open = Security::default();
        assert_eq!(open.label(), "");
        assert!(open.open());
        assert!(!open.wants_psk());

        let wep = Security {
            flags: AP_FLAG_PRIVACY,
            wpa: 0,
            rsn: 0,
        };
        assert_eq!(wep.label(), "WEP");
        assert!(!wep.wants_psk());

        // SAE alone is WPA3 and not WPA2: nmcli tests RSN for PSK or 802.1X, and a
        // pure-SAE network advertises neither.
        let wpa3 = Security {
            flags: AP_FLAG_PRIVACY,
            wpa: 0,
            rsn: SEC_KEY_MGMT_SAE | 0x88,
        };
        assert_eq!(wpa3.label(), "WPA3");

        let transition = Security {
            flags: AP_FLAG_PRIVACY,
            wpa: 0,
            rsn: SEC_KEY_MGMT_PSK | SEC_KEY_MGMT_SAE,
        };
        assert_eq!(transition.label(), "WPA2 WPA3");

        let owe = Security {
            flags: 0,
            wpa: 0,
            rsn: SEC_KEY_MGMT_OWE,
        };
        assert_eq!(owe.label(), "OWE");
        assert!(!owe.wants_psk());

        let eap = Security {
            flags: AP_FLAG_PRIVACY,
            wpa: 0,
            rsn: SEC_KEY_MGMT_802_1X,
        };
        assert_eq!(eap.label(), "WPA2 802.1X");
        assert!(eap.enterprise());
        assert!(!eap.wants_psk());

        let suite_b = Security {
            flags: AP_FLAG_PRIVACY,
            wpa: 0,
            rsn: SEC_KEY_MGMT_802_1X | SEC_KEY_MGMT_EAP_SUITE_B_192,
        };
        assert_eq!(suite_b.label(), "WPA2 802.1X WPA-EAP-SUITE-B-192");
    }

    #[test]
    fn wps_in_the_flags_is_not_mistaken_for_a_security_mode() {
        let with_wps = Security {
            flags: AP_FLAG_PRIVACY | AP_FLAG_WPS,
            wpa: 0,
            rsn: SEC_KEY_MGMT_PSK,
        };
        assert!(with_wps.wps());
        assert!(!with_wps.wep());
        assert_eq!(with_wps.label(), "WPA2");
    }

    #[test]
    fn an_ssid_that_is_not_utf8_decodes_without_panicking() {
        // 0xFF is not a legal UTF-8 byte anywhere.
        let broken = Ssid::new(vec![b'K', 0xff, 0xfe, b'O']);
        assert!(!broken.is_utf8());
        assert_eq!(broken.to_lossy(), "K\u{fffd}\u{fffd}O");
        assert_eq!(broken.as_bytes(), &[b'K', 0xff, 0xfe, b'O']);
        assert!(!broken.is_hidden());

        // A truncated multi-byte sequence, which is what a clipped 32-octet SSID
        // actually looks like on the wire.
        let clipped = Ssid::new(vec![0xe2, 0x98]);
        assert!(!clipped.is_utf8());
        assert_eq!(clipped.to_lossy(), "\u{fffd}");
    }

    #[test]
    fn an_emoji_ssid_survives_the_round_trip_whole() {
        let bytes = "cafe \u{2615}\u{1f6dc}".as_bytes().to_vec();
        let ssid = Ssid::new(bytes.clone());
        assert!(ssid.is_utf8());
        assert_eq!(ssid.to_lossy(), "cafe \u{2615}\u{1f6dc}");
        assert_eq!(ssid.as_bytes(), bytes.as_slice());
    }

    #[test]
    fn a_zero_length_ssid_is_hidden_rather_than_unnamed() {
        let hidden = Ssid::new(Vec::new());
        assert!(hidden.is_hidden());
        assert_eq!(hidden.to_lossy(), "");
        assert!(hidden.is_utf8());
    }

    /// Real bytes off this seat: `Ssid ay 9 84 111 117 114 115 97 110 97 107`.
    #[test]
    fn the_associated_access_point_decodes_from_the_bytes_the_bus_sent() {
        let ssid = Ssid::new(vec![84, 111, 117, 114, 115, 97, 110, 97, 107]);
        assert_eq!(ssid.to_lossy(), "Toursanak");
    }

    fn ap(ssid: &str, bssid: &str, strength: u8, active: bool) -> AccessPoint {
        AccessPoint {
            path: format!("/ap/{bssid}"),
            ssid: Ssid::new(ssid.as_bytes().to_vec()),
            strength,
            frequency: 2412,
            hw_address: bssid.to_owned(),
            max_bitrate: 0,
            bandwidth: 20,
            security: Security::default(),
            last_seen: 0,
            active,
        }
    }

    #[test]
    fn the_per_ssid_view_keeps_the_associated_radio_over_the_louder_one() {
        let all = vec![
            ap("D28", "aa", 45, false),
            ap("Toursanak", "bb", 40, true),
            ap("Toursanak", "cc", 90, false),
            ap("D28", "dd", 70, false),
            ap("", "ee", 99, false),
        ];

        let best = strongest_per_ssid(&all);
        assert_eq!(best.len(), 2, "hidden ssid must not become an entry");

        let toursanak = best.iter().find(|a| a.ssid.to_lossy() == "Toursanak").unwrap();
        assert_eq!(toursanak.hw_address, "bb");
        let d28 = best.iter().find(|a| a.ssid.to_lossy() == "D28").unwrap();
        assert_eq!(d28.hw_address, "dd");
    }

    #[test]
    fn the_bands_this_seat_scanned_land_where_they_belong() {
        let mut two = ap("x", "aa", 1, false);
        two.frequency = 2457;
        assert_eq!(two.band_ghz(), 2);
        two.frequency = 5180;
        assert_eq!(two.band_ghz(), 5);
        two.frequency = 6135;
        assert_eq!(two.band_ghz(), 6);
    }
}
