//! The NDJSON wire format of `audiod/PROTOCOL.md`, and nothing that is not in it.

use serde::{Deserialize, Serialize};

use koompi_service::{Error, Result};

use crate::model::{AudioState, Node};

/// `Audio.qml:18` and the `[0, 2]` range `set_volume` accepts.
pub const MAX_VOLUME: f64 = 2.0;

pub const PROTOCOL_VERSION: u32 = 1;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Hello {
    pub protocol: u32,
    #[serde(default)]
    pub daemon: String,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub pipewire: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Reply {
    #[serde(default)]
    pub id: Option<u64>,
    pub ok: bool,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub message: Option<String>,
}

impl Reply {
    pub fn outcome(&self) -> Result<()> {
        if self.ok {
            return Ok(());
        }
        let code = self.error.as_deref().unwrap_or("error");
        match &self.message {
            Some(message) => Err(Error::Protocol(format!("audiod {code}: {message}"))),
            None => Err(Error::Protocol(format!("audiod {code}"))),
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct DaemonError {
    pub error: String,
    #[serde(default)]
    pub message: String,
    #[serde(default)]
    pub res: Option<i32>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Unavailable {
    pub reason: String,
    #[serde(default)]
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Message {
    Hello(Hello),
    State(AudioState),
    NodeAdded {
        node: Node,
    },
    NodeChanged {
        node: Node,
    },
    NodeRemoved {
        id: u32,
    },
    DefaultsChanged {
        #[serde(default)]
        default_sink: Option<String>,
        #[serde(default)]
        default_source: Option<String>,
    },
    Reply(Reply),
    Error(DaemonError),
    Unavailable(Unavailable),
    /// A type this build does not know, which the protocol requires a reader to ignore so
    /// the daemon can grow without a version bump.
    #[serde(other)]
    Unknown,
}

impl Message {
    pub fn parse(line: &str) -> Result<Self> {
        serde_json::from_str(line).map_err(|e| Error::Protocol(format!("audiod line: {e}")))
    }

    pub fn to_line(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|e| format!(r#"{{"type":"error","error":"{e}"}}"#))
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum Command {
    Ping { id: u64 },
    GetState { id: u64 },
    SetVolume { id: u64, node: u32, volume: f64 },
    SetMute { id: u64, node: u32, mute: bool },
    SetDefaultSink { id: u64, name: String },
    SetDefaultSource { id: u64, name: String },
    Quit { id: u64 },
}

impl Command {
    pub fn id(&self) -> u64 {
        match self {
            Self::Ping { id }
            | Self::GetState { id }
            | Self::SetVolume { id, .. }
            | Self::SetMute { id, .. }
            | Self::SetDefaultSink { id, .. }
            | Self::SetDefaultSource { id, .. }
            | Self::Quit { id } => *id,
        }
    }

    /// One command per line, `\n` terminated, as the protocol frames stdin.
    pub fn line(&self) -> String {
        let mut line = serde_json::to_string(self).unwrap_or_default();
        line.push('\n');
        line
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_command_serialises_to_the_documented_line() {
        assert_eq!(Command::Ping { id: 1 }.line(), "{\"cmd\":\"ping\",\"id\":1}\n");
        assert_eq!(
            Command::GetState { id: 2 }.line(),
            "{\"cmd\":\"get_state\",\"id\":2}\n"
        );
        assert_eq!(
            Command::SetVolume {
                id: 3,
                node: 85,
                volume: 0.6816,
            }
            .line(),
            "{\"cmd\":\"set_volume\",\"id\":3,\"node\":85,\"volume\":0.6816}\n"
        );
        assert_eq!(
            Command::SetMute {
                id: 4,
                node: 85,
                mute: false,
            }
            .line(),
            "{\"cmd\":\"set_mute\",\"id\":4,\"node\":85,\"mute\":false}\n"
        );
        assert_eq!(
            Command::SetDefaultSink {
                id: 5,
                name: "alsa_output.speaker".into(),
            }
            .line(),
            "{\"cmd\":\"set_default_sink\",\"id\":5,\"name\":\"alsa_output.speaker\"}\n"
        );
        assert_eq!(
            Command::SetDefaultSource {
                id: 6,
                name: "alsa_input.mic".into(),
            }
            .line(),
            "{\"cmd\":\"set_default_source\",\"id\":6,\"name\":\"alsa_input.mic\"}\n"
        );
        assert_eq!(Command::Quit { id: 7 }.line(), "{\"cmd\":\"quit\",\"id\":7}\n");
    }

    #[test]
    fn a_command_carries_the_id_the_reply_will_echo() {
        let command = Command::SetMute {
            id: 42,
            node: 85,
            mute: true,
        };
        assert_eq!(command.id(), 42);
    }

    #[test]
    fn a_failed_reply_names_its_error_code() {
        let reply = Reply {
            id: Some(2),
            ok: false,
            error: Some("unknown_command".into()),
            message: Some("nonsense".into()),
        };
        let message = reply.outcome().unwrap_err().to_string();
        assert!(message.contains("unknown_command"), "{message}");
        assert!(message.contains("nonsense"), "{message}");

        assert!(Reply {
            id: Some(1),
            ok: true,
            error: None,
            message: None,
        }
        .outcome()
        .is_ok());
    }

    #[test]
    fn an_unknown_message_type_is_ignored_rather_than_a_parse_failure() {
        assert_eq!(
            Message::parse(r#"{"type":"something_new","payload":7}"#).unwrap(),
            Message::Unknown
        );
    }

    #[test]
    fn a_line_that_is_not_json_at_all_is_a_protocol_error() {
        let error = Message::parse("this is not json").unwrap_err();
        assert!(matches!(error, Error::Protocol(_)), "{error}");
    }
}
