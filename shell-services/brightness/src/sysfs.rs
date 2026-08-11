//! Reading the internal panel, which `Brightness.qml:129` did by forking
//! `brightnessctl g` and `brightnessctl m` inside an `sh -c`.

use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};

use koompi_service::{Error, Result};
use tokio::io::unix::AsyncFd;
use tokio::io::Interest;

use crate::panel::drm_connector;

pub const CLASS: &str = "/sys/class/backlight";

/// linux `O_NONBLOCK`
const O_NONBLOCK: i32 = 0o4000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Backlight {
    pub name: String,
    pub connector: Option<String>,
    pub raw_max: u32,
}

pub fn discover(class: &Path) -> Vec<Backlight> {
    let Ok(entries) = std::fs::read_dir(class) else {
        return Vec::new();
    };
    let mut lights: Vec<Backlight> = entries
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let name = entry.file_name().to_string_lossy().into_owned();
            Some(Backlight {
                connector: std::fs::read_link(entry.path().join("device"))
                    .ok()
                    .and_then(|target| drm_connector(&target.file_name()?.to_string_lossy())),
                raw_max: read_u32(&entry.path().join("max_brightness")).ok()?,
                name,
            })
        })
        .collect();
    lights.sort_by(|a, b| a.name.cmp(&b.name));
    lights
}

pub fn read_brightness(class: &Path, name: &str) -> Result<u32> {
    read_u32(&class.join(name).join("brightness"))
}

fn read_u32(path: &Path) -> Result<u32> {
    let text = std::fs::read_to_string(path)?;
    text.trim()
        .parse()
        .map_err(|_| Error::Protocol(format!("{} is not a number", path.display())))
}

/// `POLLPRI` on `actual_brightness`, which the backlight class raises through
/// `sysfs_notify` on every change including the ones the brightness keys make outside
/// the shell. Nothing here polls.
pub struct Watch {
    fd: AsyncFd<File>,
    path: PathBuf,
}

impl Watch {
    pub fn open(class: &Path, name: &str) -> Result<Self> {
        let path = class.join(name).join("actual_brightness");
        let file = OpenOptions::new()
            .read(true)
            .custom_flags(O_NONBLOCK)
            .open(&path)
            .map_err(|_| Error::Unavailable(path.display().to_string()))?;
        Ok(Self {
            fd: AsyncFd::with_interest(file, Interest::PRIORITY)?,
            path,
        })
    }

    /// Resolves with the value the panel moved to.
    pub async fn changed(&mut self) -> Result<u32> {
        let mut guard = self.fd.ready_mut(Interest::PRIORITY).await?;
        // Cleared before the read, not after: a change landing mid-read then leaves the
        // readiness set and we come straight back rather than losing it.
        guard.clear_ready();

        let file = guard.get_inner_mut();
        // Rewinding is what resets kernfs's event counter, so skipping it would leave
        // `POLLPRI` raised for ever.
        file.seek(SeekFrom::Start(0))?;
        let mut text = String::new();
        file.read_to_string(&mut text)?;

        text.trim()
            .parse()
            .map_err(|_| Error::Protocol(format!("{} is not a number", self.path.display())))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("koompi-brightness-{name}"));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    fn fake_backlight(class: &Path, name: &str, max: u32, current: u32) {
        let dir = class.join(name);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("max_brightness"), format!("{max}\n")).unwrap();
        std::fs::write(dir.join("brightness"), format!("{current}\n")).unwrap();
    }

    #[test]
    fn discovery_reads_the_max_and_leaves_a_directory_without_one_out() {
        let class = scratch("discover");
        fake_backlight(&class, "intel_backlight", 174545, 80291);
        std::fs::create_dir_all(class.join("not_a_backlight")).unwrap();

        let found = discover(&class);

        assert_eq!(found.len(), 1);
        assert_eq!(found[0].name, "intel_backlight");
        assert_eq!(found[0].raw_max, 174545);
        assert_eq!(read_brightness(&class, "intel_backlight").unwrap(), 80291);

        std::fs::remove_dir_all(&class).unwrap();
    }

    #[test]
    fn a_class_directory_that_does_not_exist_is_a_seat_with_no_panel() {
        assert!(discover(Path::new("/sys/class/backlight-does-not-exist")).is_empty());
    }

    #[test]
    fn a_reading_that_is_not_a_number_is_a_protocol_error_not_a_zero() {
        let class = scratch("garbage");
        fake_backlight(&class, "intel_backlight", 174545, 0);
        std::fs::write(class.join("intel_backlight/brightness"), "dim\n").unwrap();

        let error = read_brightness(&class, "intel_backlight").unwrap_err();

        assert!(matches!(error, Error::Protocol(_)));
        std::fs::remove_dir_all(&class).unwrap();
    }
}
