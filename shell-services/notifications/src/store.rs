//! D07: the history file, in the shape `Notifications.qml:267-303` already reads.
//!
//! The file on a running seat is the only copy of the user's notification history, so two
//! things hold here. The write is atomic, temp file and rename in the same directory, the
//! way `SessionRestore.qml:220` asks for `atomicWrites`, because a torn write is the whole
//! history gone. And a file that will not parse is an error rather than an empty list: a
//! reader that shrugged and carried on would write that empty list back over it.

use std::path::{Path, PathBuf};

use koompi_service::{Error, Result};
use serde::{Deserialize, Serialize};

use crate::model::{Action, Icon, Notification, Timeout, Urgency};
use crate::Hints;

/// The field names and their order are `Notifications.qml:45-57`. Order matters only so a
/// history the shell wrote and a history we wrote diff as nothing.
#[derive(Debug, Serialize, Deserialize)]
struct Record {
    #[serde(rename = "notificationId")]
    notification_id: u32,
    #[serde(default)]
    actions: Vec<ActionRecord>,
    #[serde(rename = "appIcon", default)]
    app_icon: String,
    #[serde(rename = "appName", default)]
    app_name: String,
    #[serde(default)]
    body: String,
    #[serde(default)]
    image: String,
    #[serde(default)]
    summary: String,
    #[serde(default)]
    time: u64,
    #[serde(default)]
    urgency: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct ActionRecord {
    #[serde(default)]
    identifier: String,
    #[serde(default)]
    text: String,
}

impl Record {
    fn of(notification: &Notification) -> Self {
        Self {
            notification_id: notification.id,
            actions: notification
                .actions
                .iter()
                .map(|action| ActionRecord {
                    identifier: action.identifier.clone(),
                    text: action.text.clone(),
                })
                .collect(),
            app_icon: notification.app_icon.as_str().to_owned(),
            app_name: notification.app_name.clone(),
            body: notification.body.clone(),
            // Inline pixels have no URL to write, and encoding one would mean an image
            // crate in this graph. A history entry keeps the path it can keep.
            image: notification
                .hints
                .image_path
                .as_ref()
                .map(|icon| icon.as_str().to_owned())
                .unwrap_or_default(),
            summary: notification.summary.clone(),
            time: notification.time,
            urgency: notification.hints.urgency.as_str().to_owned(),
        }
    }

    fn into_notification(self) -> Notification {
        let image_path = Icon::parse(&self.image);
        Notification {
            id: self.notification_id,
            app_name: self.app_name,
            app_icon: Icon::parse(&self.app_icon),
            summary: self.summary,
            body: self.body,
            actions: self
                .actions
                .into_iter()
                .map(|action| Action {
                    identifier: action.identifier,
                    text: action.text,
                })
                .collect(),
            hints: Hints {
                urgency: Urgency::parse(&self.urgency),
                image_path: (image_path != Icon::Empty).then_some(image_path),
                ..Hints::default()
            },
            // Restored entries are history. Nothing pops up and no timer runs for them, and
            // their sender is long gone, which is why `Notifications.qml:275` drops their
            // actions on the way in.
            timeout: Timeout::Never,
            time: self.time,
            popup: false,
        }
    }
}

pub struct Store {
    path: PathBuf,
}

impl Store {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    /// `Directories.qml:36`, resolved the way `QStandardPaths::CacheLocation` resolves it
    /// for an application named `quickshell`.
    pub fn default_path() -> PathBuf {
        let cache = std::env::var_os("XDG_CACHE_HOME")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
            .unwrap_or_else(|| PathBuf::from(".cache"));
        cache.join("quickshell/notifications/notifications.json")
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// A missing file is an empty history, which is what a first run looks like. A file that
    /// is there and will not parse is an error, so that nothing overwrites it.
    pub fn load(&self) -> Result<Vec<Notification>> {
        let text = match std::fs::read_to_string(&self.path) {
            Ok(text) => text,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(error) => return Err(Error::Io(error)),
        };
        if text.trim().is_empty() {
            return Ok(Vec::new());
        }

        let records: Vec<Record> = serde_json::from_str(&text).map_err(|error| {
            Error::Protocol(format!(
                "{} is not a notification history: {error}",
                self.path.display()
            ))
        })?;
        Ok(records.into_iter().map(Record::into_notification).collect())
    }

    pub async fn save(&self, list: &[Notification]) -> Result<()> {
        let records: Vec<Record> = list.iter().map(Record::of).collect();
        // Two spaces, matching `JSON.stringify(list, null, 2)` at `Notifications.qml:93`.
        let mut json = serde_json::to_string_pretty(&records)
            .map_err(|error| Error::Protocol(format!("cannot serialise the history: {error}")))?;
        json.push('\n');

        let path = self.path.clone();
        tokio::task::spawn_blocking(move || write_atomically(&path, json.as_bytes()))
            .await
            .map_err(|error| Error::Protocol(format!("history writer panicked: {error}")))?
    }
}

/// Rename is the atomic step, so the temp file has to share the destination's filesystem,
/// which means its directory. The fsync before it is what makes the rename mean something
/// after a power cut rather than just after a crash.
fn write_atomically(path: &Path, bytes: &[u8]) -> Result<()> {
    use std::io::Write;

    let directory = path.parent().unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(directory)?;

    let temporary = directory.join(format!(
        ".{}.{}.tmp",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("notifications.json"),
        std::process::id()
    ));

    let write = || -> std::io::Result<()> {
        let mut file = std::fs::File::create(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        std::fs::rename(&temporary, path)
    };

    write().inspect_err(|_| {
        let _ = std::fs::remove_file(&temporary);
    })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::ImageData;

    fn scratch(name: &str) -> PathBuf {
        let path = std::env::temp_dir()
            .join("koompi-notifications-tests")
            .join(format!("{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).unwrap();
        path.join("notifications.json")
    }

    fn notification(id: u32) -> Notification {
        Notification {
            id,
            app_name: "Recorder".into(),
            app_icon: Icon::Name("media-record".into()),
            summary: "Recording started".into(),
            body: "/home/userx/Videos/x.mp4".into(),
            actions: vec![Action {
                identifier: "open".into(),
                text: "Open".into(),
            }],
            hints: Hints {
                urgency: Urgency::Critical,
                image_path: Some(Icon::Path("/tmp/thumb.png".into())),
                ..Hints::default()
            },
            timeout: Timeout::Millis(3000),
            time: 1786266932702,
            popup: true,
        }
    }

    #[tokio::test]
    async fn what_is_written_is_what_the_qml_reads_back() {
        let store = Store::new(scratch("shape"));
        store.save(&[notification(77)]).await.unwrap();

        let text = std::fs::read_to_string(store.path()).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&text).unwrap();
        let entry = &parsed[0];

        // Every property `Notifications.qml:272-283` reads off an entry.
        assert_eq!(entry["notificationId"], 77);
        assert_eq!(entry["actions"][0]["identifier"], "open");
        assert_eq!(entry["actions"][0]["text"], "Open");
        assert_eq!(entry["appIcon"], "media-record");
        assert_eq!(entry["appName"], "Recorder");
        assert_eq!(entry["body"], "/home/userx/Videos/x.mp4");
        assert_eq!(entry["image"], "/tmp/thumb.png");
        assert_eq!(entry["summary"], "Recording started");
        assert_eq!(entry["time"], 1786266932702u64);
        assert_eq!(entry["urgency"], "2");

        assert!(
            text.starts_with("[\n  {\n    \"notificationId\""),
            "not the QML's indent or key order:\n{text}"
        );

        let restored = store.load().unwrap();
        assert_eq!(restored.len(), 1);
        assert_eq!(restored[0].id, 77);
        assert_eq!(restored[0].hints.urgency, Urgency::Critical);
        assert_eq!(restored[0].app_icon, Icon::Name("media-record".into()));
        assert!(!restored[0].popup, "a restored entry came back as a popup");
    }

    #[tokio::test]
    async fn inline_pixels_leave_the_history_entry_without_an_image_rather_than_an_encoded_one() {
        let mut notification = notification(1);
        notification.hints.image_path = None;
        notification.hints.image = Some(ImageData {
            width: 1,
            height: 1,
            rowstride: 4,
            has_alpha: true,
            bits_per_sample: 8,
            channels: 4,
            bytes: vec![1, 2, 3, 4],
        });

        let store = Store::new(scratch("inline"));
        store.save(&[notification]).await.unwrap();

        let parsed: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(store.path()).unwrap()).unwrap();
        assert_eq!(parsed[0]["image"], "");
    }

    /// A history the running shell wrote, in its own hand: the `image://icon/` URL
    /// Quickshell puts in `image`, urgency as a stringified number, and an entry carrying
    /// actions. Reading it and writing it back has to produce the same bytes, or the first
    /// notification after a restart rewrites the user's history into a different shape.
    #[tokio::test]
    async fn a_history_the_shell_wrote_survives_a_read_and_a_write_byte_for_byte() {
        let written_by_quickshell = r#"[
  {
    "notificationId": 65,
    "actions": [],
    "appIcon": "",
    "appName": "KOOMPI",
    "body": "/home/user/Pictures/shot.png",
    "image": "image://icon//home/user/Pictures/shot.png",
    "summary": "Screenshot saved",
    "time": 1786265820210,
    "urgency": "1"
  },
  {
    "notificationId": 77,
    "actions": [
      {
        "identifier": "open",
        "text": "Open"
      }
    ],
    "appIcon": "media-record",
    "appName": "Recorder",
    "body": "",
    "image": "",
    "summary": "Recording stopped",
    "time": 1786267774253,
    "urgency": "2"
  }
]
"#;

        let path = scratch("round-trip");
        std::fs::write(&path, written_by_quickshell).unwrap();
        let store = Store::new(&path);

        let list = store.load().unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[1].hints.urgency, Urgency::Critical);
        assert_eq!(list[1].actions[0].text, "Open");
        // Quickshell's own provider URL is not a path and not a theme name; it goes back
        // out the way it came in rather than being interpreted.
        assert_eq!(
            list[0].hints.image_path.as_ref().unwrap().as_str(),
            "image://icon//home/user/Pictures/shot.png"
        );

        store.save(&list).await.unwrap();
        assert_eq!(
            std::fs::read_to_string(&path).unwrap(),
            written_by_quickshell
        );
    }

    #[test]
    fn a_history_that_is_not_there_is_empty_and_one_that_is_broken_is_an_error() {
        let path = scratch("missing");
        assert!(Store::new(&path).load().unwrap().is_empty());

        std::fs::write(&path, "{ this is not the history }").unwrap();
        let error = Store::new(&path).load().unwrap_err();
        assert!(
            matches!(error, Error::Protocol(_)),
            "a corrupt history has to stop the load, or the next save overwrites it"
        );
    }

    #[tokio::test]
    async fn a_save_leaves_no_temp_file_behind() {
        let store = Store::new(scratch("temp"));
        store.save(&[notification(1)]).await.unwrap();
        store
            .save(&[notification(1), notification(2)])
            .await
            .unwrap();

        let left: Vec<String> = std::fs::read_dir(store.path().parent().unwrap())
            .unwrap()
            .filter_map(|entry| Some(entry.ok()?.file_name().to_string_lossy().into_owned()))
            .collect();
        assert_eq!(left, ["notifications.json"]);
        assert_eq!(store.load().unwrap().len(), 2);
    }
}
