//! The spec's `Notify` arguments as plain data, after the parts every application words
//! differently have been normalised.

/// One entry of the flat `actions` array, once it has been paired back up.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Action {
    pub identifier: String,
    pub text: String,
}

/// The spec sends actions as `[id, label, id, label, ...]`, so a sender that miscounts
/// leaves a trailing id with no label. That one is dropped and the rest kept: the pairs
/// before it are unambiguous, and refusing the whole notification over a bad last action
/// costs the user the message.
pub fn pair_actions(flat: &[String]) -> Vec<Action> {
    flat.chunks_exact(2)
        .map(|pair| Action {
            identifier: pair[0].clone(),
            text: pair[1].clone(),
        })
        .collect()
}

/// What `expire_timeout` means, which is three different things depending on its sign.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Timeout {
    /// `0`: stays until the user acts or the application closes it.
    Never,
    /// `-1`: the server decides, which is [`crate::NotificationsConfig::default_timeout`].
    ServerDefault,
    Millis(u32),
}

impl From<i32> for Timeout {
    fn from(raw: i32) -> Self {
        match raw {
            0 => Self::Never,
            positive if positive > 0 => Self::Millis(positive as u32),
            _ => Self::ServerDefault,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Urgency {
    Low,
    Normal,
    Critical,
}

impl Urgency {
    pub fn as_u8(self) -> u8 {
        match self {
            Self::Low => 0,
            Self::Normal => 1,
            Self::Critical => 2,
        }
    }

    /// The form `Notifications.qml:35` writes to the history: the number, as a string.
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Low => "0",
            Self::Normal => "1",
            Self::Critical => "2",
        }
    }

    /// Both spellings on disk: the numbers Quickshell writes today, and the words the QML
    /// falls back to when it has no notification object.
    pub fn parse(raw: &str) -> Self {
        match raw.trim().to_ascii_lowercase().as_str() {
            "0" | "low" => Self::Low,
            "2" | "critical" => Self::Critical,
            _ => Self::Normal,
        }
    }
}

impl From<u8> for Urgency {
    fn from(raw: u8) -> Self {
        match raw {
            0 => Self::Low,
            2 => Self::Critical,
            _ => Self::Normal,
        }
    }
}

/// `app_icon` and the `image-path` hint take the same three forms, and telling them apart
/// is the difference between a theme lookup and a file read.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Icon {
    Empty,
    /// A freedesktop icon name for the consumer to resolve against the current theme.
    Name(String),
    /// An absolute path, whether it arrived bare or wrapped in a `file://` URI.
    Path(String),
}

impl Icon {
    pub fn parse(raw: &str) -> Self {
        let raw = raw.trim();
        if raw.is_empty() {
            return Self::Empty;
        }
        if let Some(rest) = raw.strip_prefix("file://") {
            // file://host/path is legal and the host is almost always empty; either way the
            // path starts at the first slash.
            let path = match rest.find('/') {
                Some(cut) => &rest[cut..],
                None => rest,
            };
            return Self::Path(percent_decode(path));
        }
        if raw.starts_with('/') {
            return Self::Path(raw.to_owned());
        }
        Self::Name(raw.to_owned())
    }

    /// What goes back on disk and what a consumer resolves. Empty for [`Icon::Empty`], so
    /// the history keeps the empty string `Notifications.qml:29` expects.
    pub fn as_str(&self) -> &str {
        match self {
            Self::Empty => "",
            Self::Name(name) => name,
            Self::Path(path) => path,
        }
    }
}

/// `%20` in a `file://` URI is a space in a filename, and a consumer that opens the raw
/// text finds nothing there.
fn percent_decode(raw: &str) -> String {
    let bytes = raw.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        let decoded = (bytes[index] == b'%' && index + 2 < bytes.len())
            .then(|| {
                let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).ok()?;
                u8::from_str_radix(hex, 16).ok()
            })
            .flatten();
        match decoded {
            Some(byte) => {
                out.push(byte);
                index += 3;
            }
            None => {
                out.push(bytes[index]);
                index += 1;
            }
        }
    }
    String::from_utf8(out).unwrap_or_else(|_| raw.to_owned())
}

/// Raw as received: the application's own dimensions, stride and bytes. Turning this into a
/// texture needs a toolkit, which this crate has none of by rule, so nothing here decodes,
/// rescales or reorders a single byte.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImageData {
    pub width: i32,
    pub height: i32,
    pub rowstride: i32,
    pub has_alpha: bool,
    pub bits_per_sample: i32,
    pub channels: i32,
    pub bytes: Vec<u8>,
}

impl ImageData {
    /// GdkPixbuf pads every row but the last, so the byte count is
    /// `rowstride * (height - 1) + width * channels` and not `rowstride * height`. A buffer
    /// shorter than that is dropped: a consumer that trusted the dimensions would read past
    /// the end of it.
    pub(crate) fn validate(self) -> Option<Self> {
        let sane = self.width > 0
            && self.height > 0
            && self.bits_per_sample == 8
            && (self.channels == 3 || self.channels == 4)
            && self.has_alpha == (self.channels == 4)
            && self.rowstride >= self.width.checked_mul(self.channels)?;

        let needed = (self.rowstride as i64)
            .checked_mul(self.height as i64 - 1)?
            .checked_add((self.width as i64).checked_mul(self.channels as i64)?)?;

        (sane && self.bytes.len() as i64 >= needed).then_some(self)
    }
}

/// Why a notification stopped being shown, as the spec numbers it in `NotificationClosed`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CloseReason {
    Expired,
    Dismissed,
    /// `CloseNotification` was called for it.
    Closed,
    Undefined,
}

impl CloseReason {
    pub fn as_u32(self) -> u32 {
        match self {
            Self::Expired => 1,
            Self::Dismissed => 2,
            Self::Closed => 3,
            Self::Undefined => 4,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notification {
    pub id: u32,
    pub app_name: String,
    pub app_icon: Icon,
    pub summary: String,
    pub body: String,
    pub actions: Vec<Action>,
    pub hints: crate::Hints,
    pub timeout: Timeout,
    /// Milliseconds since the epoch, which is the `time` the history keeps
    /// (`Notifications.qml:167`).
    pub time: u64,
    /// Still wanted on screen. This goes false when the notification expires while the
    /// entry stays in the list, because the list is history and the popup is not.
    pub popup: bool,
}

impl Notification {
    pub fn action(&self, identifier: &str) -> Option<&Action> {
        self.actions
            .iter()
            .find(|action| action.identifier == identifier)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn actions_pair_up_and_an_odd_trailing_one_is_dropped() {
        let flat: Vec<String> = ["yes", "Yes", "no", "No"]
            .iter()
            .map(|s| (*s).to_owned())
            .collect();
        assert_eq!(
            pair_actions(&flat),
            [
                Action {
                    identifier: "yes".into(),
                    text: "Yes".into()
                },
                Action {
                    identifier: "no".into(),
                    text: "No".into()
                },
            ]
        );

        let malformed: Vec<String> = ["yes", "Yes", "orphan"]
            .iter()
            .map(|s| (*s).to_owned())
            .collect();
        let paired = pair_actions(&malformed);
        assert_eq!(paired.len(), 1, "a stray id took the whole notification");
        assert_eq!(paired[0].identifier, "yes");

        assert!(pair_actions(&[]).is_empty());
        assert!(pair_actions(&["lonely".to_owned()]).is_empty());
    }

    #[test]
    fn expire_timeout_means_three_different_things() {
        assert_eq!(Timeout::from(0), Timeout::Never);
        assert_eq!(Timeout::from(-1), Timeout::ServerDefault);
        // No sender means anything else by a negative number.
        assert_eq!(Timeout::from(-9000), Timeout::ServerDefault);
        assert_eq!(Timeout::from(2500), Timeout::Millis(2500));
    }

    #[test]
    fn urgency_round_trips_through_the_form_the_history_holds() {
        for urgency in [Urgency::Low, Urgency::Normal, Urgency::Critical] {
            assert_eq!(Urgency::parse(urgency.as_str()), urgency);
            assert_eq!(Urgency::from(urgency.as_u8()), urgency);
        }
        assert_eq!(Urgency::parse("critical"), Urgency::Critical);
        assert_eq!(Urgency::parse("normal"), Urgency::Normal);
        assert_eq!(Urgency::parse(""), Urgency::Normal);
        assert_eq!(Urgency::parse("7"), Urgency::Normal);
        assert_eq!(Urgency::from(9u8), Urgency::Normal);
    }

    #[test]
    fn an_icon_is_a_theme_name_a_path_or_a_uri() {
        assert_eq!(Icon::parse(""), Icon::Empty);
        assert_eq!(Icon::parse("  "), Icon::Empty);
        assert_eq!(
            Icon::parse("dialog-information"),
            Icon::Name("dialog-information".into())
        );
        assert_eq!(
            Icon::parse("/usr/share/icons/x.png"),
            Icon::Path("/usr/share/icons/x.png".into())
        );
        assert_eq!(
            Icon::parse("file:///home/userx/my%20icon.png"),
            Icon::Path("/home/userx/my icon.png".into())
        );
        assert_eq!(
            Icon::parse("file://localhost/tmp/x.png"),
            Icon::Path("/tmp/x.png".into())
        );
        // A stray percent is a percent, not a parse failure.
        assert_eq!(
            Icon::parse("file:///tmp/100%.png").as_str(),
            "/tmp/100%.png"
        );
        assert_eq!(Icon::Empty.as_str(), "");
    }

    fn image(width: i32, height: i32, rowstride: i32, channels: i32, len: usize) -> ImageData {
        ImageData {
            width,
            height,
            rowstride,
            has_alpha: channels == 4,
            bits_per_sample: 8,
            channels,
            bytes: vec![0; len],
        }
    }

    #[test]
    fn image_data_shorter_than_its_own_geometry_is_dropped() {
        // Padded stride, so the buffer is short of rowstride * height on purpose.
        assert!(image(3, 3, 16, 4, 16 * 2 + 3 * 4).validate().is_some());
        assert!(image(3, 3, 16, 4, 16 * 2 + 3 * 4 - 1).validate().is_none());
        assert!(image(0, 3, 12, 4, 64).validate().is_none());
        assert!(image(3, 3, 4, 4, 64).validate().is_none(), "stride < a row");
        assert!(image(3, 3, 12, 2, 64).validate().is_none(), "2 channels");

        let mut wrong_depth = image(3, 3, 12, 4, 64);
        wrong_depth.bits_per_sample = 16;
        assert!(wrong_depth.validate().is_none());

        let mut lying_alpha = image(3, 3, 12, 3, 64);
        lying_alpha.has_alpha = true;
        assert!(lying_alpha.validate().is_none());
    }

    #[test]
    fn close_reasons_keep_the_numbers_the_spec_gives_them() {
        assert_eq!(CloseReason::Expired.as_u32(), 1);
        assert_eq!(CloseReason::Dismissed.as_u32(), 2);
        assert_eq!(CloseReason::Closed.as_u32(), 3);
        assert_eq!(CloseReason::Undefined.as_u32(), 4);
    }
}
