// Where "which window has focus" comes from.
//
// The daemon is compositor-agnostic on purpose: Hyprland answers today, and
// otto has to answer the same question later. That is one trait with two
// methods, not a layer - the whole Hyprland coupling in the Zig daemon this
// replaces is 109 lines.

use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ActiveWindow {
    pub pid: i64,
    pub xwayland: bool,
    pub class: String,
    pub address: String,
}

/// A compositor that can name the focused window and say when it changed.
pub trait FocusSource {
    /// Blocks until something happened that could change which menu the bar
    /// should show. Returns on every such event, coalescing is the caller's job.
    fn wait_for_change(&mut self) -> io::Result<()>;

    fn active_window(&mut self) -> io::Result<ActiveWindow>;
}

pub struct Hyprland {
    signature: String,
    runtime_dir: PathBuf,
    events: UnixStream,
    pending: Vec<u8>,
}

impl Hyprland {
    pub fn from_env() -> io::Result<Self> {
        let signature = std::env::var("HYPRLAND_INSTANCE_SIGNATURE").map_err(|_| {
            io::Error::new(
                io::ErrorKind::NotFound,
                "HYPRLAND_INSTANCE_SIGNATURE is unset; not inside a Hyprland session",
            )
        })?;
        let runtime_dir = std::env::var("XDG_RUNTIME_DIR")
            .map(PathBuf::from)
            .map_err(|_| io::Error::new(io::ErrorKind::NotFound, "XDG_RUNTIME_DIR is unset"))?;

        let events = UnixStream::connect(socket_path(&runtime_dir, &signature, ".socket2.sock"))?;
        Ok(Self {
            signature,
            runtime_dir,
            events,
            pending: Vec::new(),
        })
    }

    fn request(&self, body: &str) -> io::Result<String> {
        let mut sock =
            UnixStream::connect(socket_path(&self.runtime_dir, &self.signature, ".socket.sock"))?;
        sock.write_all(body.as_bytes())?;
        let mut reply = String::new();
        sock.take(1 << 20).read_to_string(&mut reply)?;
        Ok(reply)
    }
}

fn socket_path(runtime_dir: &Path, signature: &str, name: &str) -> PathBuf {
    runtime_dir.join("hypr").join(signature).join(name)
}

impl FocusSource for Hyprland {
    fn wait_for_change(&mut self) -> io::Result<()> {
        let mut buf = [0u8; 4096];
        loop {
            // Drain whole lines already buffered before reading again, or an
            // event that arrived in the same packet as the previous one is lost.
            while let Some(nl) = self.pending.iter().position(|&b| b == b'\n') {
                let line: Vec<u8> = self.pending.drain(..=nl).collect();
                let line = String::from_utf8_lossy(&line[..line.len() - 1]).into_owned();
                if is_focus_event(&line) {
                    return Ok(());
                }
            }
            let n = self.events.read(&mut buf)?;
            if n == 0 {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "hyprland closed the event socket",
                ));
            }
            self.pending.extend_from_slice(&buf[..n]);
        }
    }

    /// Asks Hyprland for the focused window over its request socket. Spawning
    /// hyprctl on every focus change would cost a process; this is the same wire.
    fn active_window(&mut self) -> io::Result<ActiveWindow> {
        let reply = self.request("j/activewindow")?;
        Ok(parse_active_window(&reply))
    }
}

/// Hyprland answers with `{}` when nothing is focused, and the daemon must treat
/// that as "no window" rather than an error.
pub fn parse_active_window(json: &str) -> ActiveWindow {
    let value: serde_json::Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(_) => return ActiveWindow::default(),
    };
    ActiveWindow {
        pid: value.get("pid").and_then(|v| v.as_i64()).unwrap_or(0),
        xwayland: value
            .get("xwayland")
            .and_then(|v| v.as_bool())
            .unwrap_or(false),
        class: value
            .get("class")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_owned(),
        address: value
            .get("address")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_owned(),
    }
}

/// True when the line is one of the events that can change which menu the bar
/// should be showing.
pub fn is_focus_event(line: &str) -> bool {
    const EVENTS: [&str; 5] = [
        "activewindow>>",
        "activewindowv2>>",
        "closewindow>>",
        "focusedmon>>",
        "workspace>>",
    ];
    EVENTS.iter().any(|e| line.starts_with(e))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Same cases as src/hypr.zig's own test.
    #[test]
    fn is_focus_event_picks_the_events_that_move_focus() {
        assert!(is_focus_event("activewindow>>kitty,zsh"));
        assert!(is_focus_event("activewindowv2>>55aa"));
        assert!(is_focus_event("closewindow>>55aa"));
        assert!(!is_focus_event("createworkspace>>2"));
        assert!(!is_focus_event("monitoradded>>DP-1"));
    }

    #[test]
    fn parse_active_window_reads_the_fields_the_daemon_uses() {
        let got = parse_active_window(
            r#"{"address":"0x55aa","class":"kitty","pid":4242,"xwayland":true,"title":"zsh"}"#,
        );
        assert_eq!(
            got,
            ActiveWindow {
                pid: 4242,
                xwayland: true,
                class: "kitty".into(),
                address: "0x55aa".into(),
            }
        );
    }

    #[test]
    fn parse_active_window_treats_no_focus_as_no_window() {
        assert_eq!(parse_active_window("{}"), ActiveWindow::default());
        assert_eq!(parse_active_window("not json"), ActiveWindow::default());
    }
}
