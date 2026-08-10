//! The two sockets, and nothing between us and them. No `hyprctl` process is spawned
//! anywhere in this crate; `hyprctl` is itself only a client of these sockets.

use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;
use tokio::io::AsyncWriteExt;
use tokio::net::UnixStream;

use koompi_service::{Error, Result};

/// Where the instance directory lives on Hyprland 0.41 and later. Older builds used
/// `/tmp/hypr/$HIS`, which is why the fallback exists.
const RUNTIME_PARENT: &str = "hypr";
const LEGACY_PARENT: &str = "/tmp/hypr";

/// No signature in the environment means no compositor to talk to, which is
/// [`Error::Unavailable`] rather than a failure: a headless seat is a working seat.
pub fn resolve_instance_dir(signature: Option<&str>, runtime: Option<&str>) -> Result<PathBuf> {
    let signature = signature.filter(|s| !s.is_empty());
    let Some(signature) = signature else {
        return Err(Error::Unavailable("hyprland".into()));
    };

    let mut candidates = Vec::new();
    if let Some(runtime) = runtime {
        candidates.push(Path::new(runtime).join(RUNTIME_PARENT).join(signature));
    }
    candidates.push(Path::new(LEGACY_PARENT).join(signature));

    candidates
        .into_iter()
        .find(|dir| dir.join(".socket.sock").exists())
        .ok_or_else(|| Error::Unavailable("hyprland".into()))
}

#[derive(Debug, Clone)]
pub struct Ipc {
    instance_dir: PathBuf,
}

impl Ipc {
    pub fn from_env() -> Result<Self> {
        let signature = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").ok();
        let runtime = std::env::var("XDG_RUNTIME_DIR").ok();
        Ok(Self {
            instance_dir: resolve_instance_dir(signature.as_deref(), runtime.as_deref())?,
        })
    }

    pub fn new(instance_dir: impl Into<PathBuf>) -> Self {
        Self {
            instance_dir: instance_dir.into(),
        }
    }

    pub fn instance_dir(&self) -> &Path {
        &self.instance_dir
    }

    pub fn command_socket(&self) -> PathBuf {
        self.instance_dir.join(".socket.sock")
    }

    pub fn event_socket(&self) -> PathBuf {
        self.instance_dir.join(".socket2.sock")
    }

    pub async fn events(&self) -> Result<UnixStream> {
        Ok(UnixStream::connect(self.event_socket()).await?)
    }

    /// One request, one connection: the compositor answers and closes.
    pub async fn request(&self, command: &str) -> Result<String> {
        let mut stream = UnixStream::connect(self.command_socket()).await?;
        stream.write_all(command.as_bytes()).await?;
        stream.shutdown().await?;

        let mut reply = Vec::new();
        tokio::io::AsyncReadExt::read_to_end(&mut stream, &mut reply).await?;
        String::from_utf8(reply).map_err(|e| Error::Protocol(format!("{command}: {e}")))
    }

    pub async fn request_json<T: DeserializeOwned>(&self, command: &str) -> Result<T> {
        let reply = self.request(command).await?;
        serde_json::from_str(&reply).map_err(|e| Error::Protocol(format!("{command}: {e}")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn socket_names_hang_off_the_instance_directory() {
        let ipc = Ipc::new("/run/user/1000/hypr/sig");
        assert_eq!(
            ipc.command_socket(),
            Path::new("/run/user/1000/hypr/sig/.socket.sock")
        );
        assert_eq!(
            ipc.event_socket(),
            Path::new("/run/user/1000/hypr/sig/.socket2.sock")
        );
    }

    #[test]
    fn no_instance_signature_is_unavailable_rather_than_an_error() {
        assert!(matches!(
            resolve_instance_dir(None, Some("/run/user/1000")),
            Err(Error::Unavailable(_))
        ));
        assert!(matches!(
            resolve_instance_dir(Some(""), Some("/run/user/1000")),
            Err(Error::Unavailable(_))
        ));
        assert!(matches!(
            resolve_instance_dir(Some("sig-that-never-ran"), Some("/run/user/1000")),
            Err(Error::Unavailable(_))
        ));
    }

    #[test]
    fn the_running_session_resolves_through_xdg_runtime_dir() {
        let (Ok(signature), Ok(runtime)) = (
            std::env::var("HYPRLAND_INSTANCE_SIGNATURE"),
            std::env::var("XDG_RUNTIME_DIR"),
        ) else {
            return;
        };

        let dir = resolve_instance_dir(Some(&signature), Some(&runtime)).unwrap();
        assert_eq!(dir, Path::new(&runtime).join("hypr").join(&signature));
        assert!(dir.join(".socket2.sock").exists());
    }

    #[tokio::test]
    async fn a_socket_that_is_not_there_is_an_io_error() {
        let err = Ipc::new("/nonexistent").request("j/monitors").await.unwrap_err();
        assert!(matches!(err, Error::Io(_)), "got {err:?}");
    }
}
