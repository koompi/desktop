//! The state `Audio.qml:15-46` publishes, carried in the daemon's own field order so a
//! snapshot printed here diffs by eye against a snapshot printed by `audiod`.

use serde::{Deserialize, Serialize};

use crate::proto::{DaemonError, Hello, Message, Unavailable};

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Node {
    pub id: u32,
    #[serde(default)]
    pub serial: Option<u64>,
    pub name: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub nickname: Option<String>,
    #[serde(default)]
    pub application_name: Option<String>,
    #[serde(default)]
    pub media_class: String,
    #[serde(default)]
    pub is_sink: bool,
    #[serde(default)]
    pub is_stream: bool,
    #[serde(default)]
    pub is_default: bool,
    #[serde(default)]
    pub ready: bool,
    #[serde(default)]
    pub volume: Option<f64>,
    #[serde(default)]
    pub channel_volumes: Vec<f64>,
    #[serde(default)]
    pub mute: Option<bool>,
}

impl Node {
    /// `Audio.qml:22-24`.
    pub fn friendly_name(&self) -> &str {
        first_non_empty([self.nickname.as_deref(), self.description.as_deref()]).unwrap_or("Unknown")
    }

    /// `Audio.qml:25-27`, the label a stream is drawn with.
    pub fn display_name(&self) -> &str {
        first_non_empty([self.application_name.as_deref(), self.description.as_deref()])
            .unwrap_or(&self.name)
    }
}

fn first_non_empty<const N: usize>(candidates: [Option<&str>; N]) -> Option<&str> {
    candidates
        .into_iter()
        .flatten()
        .find(|value| !value.is_empty())
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct AudioState {
    #[serde(default)]
    pub serial: u64,
    #[serde(default)]
    pub ready: bool,
    #[serde(default)]
    pub default_sink: Option<String>,
    #[serde(default)]
    pub default_source: Option<String>,
    #[serde(default)]
    pub output_devices: Vec<Node>,
    #[serde(default)]
    pub input_devices: Vec<Node>,
    #[serde(default)]
    pub output_streams: Vec<Node>,
    #[serde(default)]
    pub input_streams: Vec<Node>,
}

impl AudioState {
    pub fn nodes(&self) -> impl Iterator<Item = &Node> {
        self.output_devices
            .iter()
            .chain(&self.input_devices)
            .chain(&self.output_streams)
            .chain(&self.input_streams)
    }

    pub fn node(&self, id: u32) -> Option<&Node> {
        self.nodes().find(|node| node.id == id)
    }

    /// `Audio.qml:16`, the node the volume keys act on.
    pub fn sink(&self) -> Option<&Node> {
        self.output_devices.iter().find(|node| node.is_default)
    }

    /// `Audio.qml:17`.
    pub fn source(&self) -> Option<&Node> {
        self.input_devices.iter().find(|node| node.is_default)
    }

    /// True when the message moved the state, so a `watch` only wakes consumers on a real
    /// change.
    pub fn apply(&mut self, message: &Message) -> bool {
        match message {
            Message::State(snapshot) => {
                let mut next = snapshot.clone();
                next.refresh_default_flags();
                let changed = *self != next;
                *self = next;
                changed
            }
            Message::NodeAdded { node } | Message::NodeChanged { node } => self.upsert(node.clone()),
            Message::NodeRemoved { id } => self.remove(*id),
            Message::DefaultsChanged {
                default_sink,
                default_source,
            } => {
                let mut changed = false;
                changed |= replace(&mut self.default_sink, default_sink.clone());
                changed |= replace(&mut self.default_source, default_source.clone());
                changed | self.refresh_default_flags()
            }
            Message::Unavailable(_) => replace(&mut self.ready, false),
            _ => false,
        }
    }

    fn upsert(&mut self, mut node: Node) -> bool {
        node.is_default = self.is_default(&node);
        let changed = self.take(node.id).as_ref() != Some(&node);
        insert_sorted(self.bucket_mut(&node), node);
        changed
    }

    fn remove(&mut self, id: u32) -> bool {
        self.take(id).is_some()
    }

    /// A node is removed from every bucket, not only the one its current class implies:
    /// `media.class` can change under us and a node must never appear twice.
    fn take(&mut self, id: u32) -> Option<Node> {
        let mut found = None;
        for bucket in self.buckets_mut() {
            if let Some(index) = bucket.iter().position(|node| node.id == id) {
                found = Some(bucket.remove(index));
            }
        }
        found
    }

    fn buckets_mut(&mut self) -> [&mut Vec<Node>; 4] {
        [
            &mut self.output_devices,
            &mut self.input_devices,
            &mut self.output_streams,
            &mut self.input_streams,
        ]
    }

    fn bucket_mut(&mut self, node: &Node) -> &mut Vec<Node> {
        match (node.is_sink, node.is_stream) {
            (true, false) => &mut self.output_devices,
            (false, false) => &mut self.input_devices,
            (true, true) => &mut self.output_streams,
            (false, true) => &mut self.input_streams,
        }
    }

    /// `is_default` on the wire is a snapshot taken when the message was written, so the
    /// protocol says to recompute it from the name rather than cache the flag.
    fn is_default(&self, node: &Node) -> bool {
        if node.is_stream {
            return false;
        }
        let default = match node.is_sink {
            true => &self.default_sink,
            false => &self.default_source,
        };
        default.as_deref() == Some(node.name.as_str())
    }

    fn refresh_default_flags(&mut self) -> bool {
        let sink = self.default_sink.clone();
        let source = self.default_source.clone();
        let mut changed = false;
        for node in self.nodes_mut() {
            let expected = match node.is_stream {
                true => false,
                false => {
                    let default = match node.is_sink {
                        true => &sink,
                        false => &source,
                    };
                    default.as_deref() == Some(node.name.as_str())
                }
            };
            changed |= replace(&mut node.is_default, expected);
        }
        changed
    }

    fn nodes_mut(&mut self) -> impl Iterator<Item = &mut Node> {
        self.output_devices
            .iter_mut()
            .chain(&mut self.input_devices)
            .chain(&mut self.output_streams)
            .chain(&mut self.input_streams)
    }
}

/// Everything the daemon says about itself and about failures that are not tied to a
/// command, kept beside the state so no field the protocol defines is dropped.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct DaemonStatus {
    pub running: bool,
    pub hello: Option<Hello>,
    pub last_error: Option<DaemonError>,
    pub unavailable: Option<Unavailable>,
}

fn insert_sorted(bucket: &mut Vec<Node>, node: Node) {
    let at = bucket.partition_point(|existing| existing.id < node.id);
    bucket.insert(at, node);
}

fn replace<T: PartialEq>(current: &mut T, next: T) -> bool {
    if *current == next {
        return false;
    }
    *current = next;
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(id: u32, name: &str, is_sink: bool) -> Node {
        Node {
            id,
            name: name.into(),
            is_sink,
            ready: true,
            volume: Some(1.0),
            ..Node::default()
        }
    }

    fn stream(id: u32, name: &str) -> Node {
        Node {
            id,
            name: name.into(),
            is_sink: true,
            is_stream: true,
            ..Node::default()
        }
    }

    #[test]
    fn a_node_lands_in_the_bucket_its_flags_imply_sorted_by_id() {
        let mut state = AudioState::default();
        assert!(state.apply(&Message::NodeAdded {
            node: device(86, "headphones", true)
        }));
        assert!(state.apply(&Message::NodeAdded {
            node: device(85, "speaker", true)
        }));
        assert!(state.apply(&Message::NodeAdded {
            node: device(90, "mic", false)
        }));
        assert!(state.apply(&Message::NodeAdded {
            node: stream(115, "pw-play")
        }));

        assert_eq!(
            state.output_devices.iter().map(|n| n.id).collect::<Vec<_>>(),
            [85, 86]
        );
        assert_eq!(state.input_devices.len(), 1);
        assert_eq!(state.output_streams.len(), 1);
        assert!(state.input_streams.is_empty());
    }

    #[test]
    fn a_repeated_node_replaces_rather_than_duplicates_and_reports_no_change() {
        let mut state = AudioState::default();
        state.apply(&Message::NodeAdded {
            node: stream(115, "pw-play"),
        });

        assert!(!state.apply(&Message::NodeChanged {
            node: stream(115, "pw-play")
        }));
        assert_eq!(state.output_streams.len(), 1);

        let mut louder = stream(115, "pw-play");
        louder.ready = true;
        louder.volume = Some(0.5);
        assert!(state.apply(&Message::NodeChanged { node: louder }));
        assert_eq!(state.output_streams.len(), 1);
        assert_eq!(state.output_streams[0].volume, Some(0.5));
    }

    #[test]
    fn the_default_flag_is_recomputed_from_the_name_never_taken_from_the_wire() {
        let mut state = AudioState {
            default_sink: Some("speaker".into()),
            ..AudioState::default()
        };

        let mut lying = device(85, "speaker", true);
        lying.is_default = false;
        state.apply(&Message::NodeAdded { node: lying });
        assert!(state.sink().is_some());

        let mut also_lying = device(86, "headphones", true);
        also_lying.is_default = true;
        state.apply(&Message::NodeAdded { node: also_lying });
        assert_eq!(state.sink().map(|n| n.id), Some(85));

        assert!(state.apply(&Message::DefaultsChanged {
            default_sink: Some("headphones".into()),
            default_source: None,
        }));
        assert_eq!(state.sink().map(|n| n.id), Some(86));
    }

    #[test]
    fn a_stream_never_claims_to_be_a_default() {
        let mut state = AudioState {
            default_sink: Some("pw-play".into()),
            ..AudioState::default()
        };
        state.apply(&Message::NodeAdded {
            node: stream(115, "pw-play"),
        });
        assert!(!state.output_streams[0].is_default);
    }

    #[test]
    fn removing_a_node_that_was_never_announced_changes_nothing() {
        let mut state = AudioState::default();
        state.apply(&Message::NodeAdded {
            node: stream(115, "pw-play"),
        });

        assert!(!state.apply(&Message::NodeRemoved { id: 999 }));
        assert!(state.apply(&Message::NodeRemoved { id: 115 }));
        assert!(state.output_streams.is_empty());
    }

    #[test]
    fn a_node_that_changes_direction_does_not_appear_twice() {
        let mut state = AudioState::default();
        state.apply(&Message::NodeAdded {
            node: device(85, "dual", true),
        });
        state.apply(&Message::NodeChanged {
            node: device(85, "dual", false),
        });

        assert!(state.output_devices.is_empty());
        assert_eq!(state.input_devices.len(), 1);
        assert_eq!(state.nodes().count(), 1);
    }

    #[test]
    fn the_friendly_name_falls_back_the_way_the_qml_does() {
        let mut node = device(85, "alsa_output.speaker", true);
        assert_eq!(node.friendly_name(), "Unknown");
        assert_eq!(node.display_name(), "alsa_output.speaker");

        node.description = Some("HD Audio Speaker".into());
        assert_eq!(node.friendly_name(), "HD Audio Speaker");
        assert_eq!(node.display_name(), "HD Audio Speaker");

        node.nickname = Some("Speaker".into());
        node.application_name = Some("pw-play".into());
        assert_eq!(node.friendly_name(), "Speaker");
        assert_eq!(node.display_name(), "pw-play");
    }
}
