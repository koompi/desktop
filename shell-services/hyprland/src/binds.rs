//! D02. The parser is `HyprlandKeybinds.qml:25-75` lifted; only the transport changed.

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Keybind {
    pub bind_type: String,
    pub modmask: u32,
    pub submap: String,
    pub key: String,
    pub keycode: i64,
    pub catchall: bool,
    pub description: String,
    pub dispatcher: String,
    pub arg: String,
}

/// Parses the plain-text form of the `binds` reply: an unindented bind type, then one
/// tab-indented `name: value` per field.
///
/// Values contain colons of their own ("mouse:273"), so only the first splits.
pub fn parse_binds(text: &str) -> Vec<Keybind> {
    let mut binds = Vec::new();
    let mut current: Option<Keybind> = None;

    for line in text.split('\n') {
        if line.is_empty() {
            continue;
        }

        let Some(field) = line.strip_prefix('\t') else {
            binds.extend(current.take());
            current = Some(Keybind {
                bind_type: line.trim().to_string(),
                ..Default::default()
            });
            continue;
        };

        let Some(bind) = current.as_mut() else {
            continue;
        };
        let Some((name, value)) = field.split_once(':') else {
            continue;
        };
        let value = value.trim();

        match name {
            "modmask" => bind.modmask = value.parse().unwrap_or(0),
            "keycode" => bind.keycode = value.parse().unwrap_or(0),
            "catchall" => bind.catchall = value == "true",
            "submap" => bind.submap = value.to_string(),
            "key" => bind.key = value.to_string(),
            "description" => bind.description = value.to_string(),
            "dispatcher" => bind.dispatcher = value.to_string(),
            "arg" => bind.arg = value.to_string(),
            _ => {}
        }
    }

    binds.extend(current);
    binds
}

/// The `Group: action` prefixes the cheatsheet groups by, `HyprlandKeybinds.qml:77-89`.
pub fn categories_of(binds: &[Keybind]) -> Vec<String> {
    let mut groups: Vec<String> = Vec::new();
    for bind in binds {
        let Some((group, _)) = bind.description.split_once(':') else {
            continue;
        };
        if group.is_empty() {
            continue;
        }
        if !groups.iter().any(|g| g == group) {
            groups.push(group.to_string());
        }
    }
    groups
}

#[cfg(test)]
mod tests {
    use super::*;

    const REAL: &str = include_str!("../tests/fixtures/binds.txt");

    #[test]
    fn parses_captured_binds_output() {
        let binds = parse_binds(REAL);
        assert_eq!(binds.len(), 10);

        let first = &binds[0];
        assert_eq!(first.bind_type, "bindd");
        assert_eq!(first.modmask, 64);
        assert_eq!(first.key, "SUPER_L");
        assert_eq!(first.description, "Shell: Toggle search");
        assert_eq!(first.dispatcher, "__lua");
        assert_eq!(first.arg, "12");
        assert!(!first.catchall);
        assert_eq!(first.submap, "");
    }

    #[test]
    fn a_value_containing_a_colon_survives() {
        let mouse = parse_binds(REAL)
            .into_iter()
            .find(|b| b.key.starts_with("mouse"))
            .expect("capture contains a mouse bind");
        assert_eq!(mouse.key, "mouse:273");
        assert_eq!(mouse.modmask, 73);
    }

    #[test]
    fn submap_binds_keep_their_submap() {
        let binds = parse_binds(REAL);
        let submapped: Vec<&Keybind> = binds.iter().filter(|b| !b.submap.is_empty()).collect();
        assert!(!submapped.is_empty());
        assert!(submapped.iter().all(|b| b.submap == "virtual-machine"));
    }

    #[test]
    fn every_captured_block_yields_exactly_one_bind() {
        let blocks = REAL
            .lines()
            .filter(|l| !l.is_empty() && !l.starts_with('\t'))
            .count();
        assert_eq!(parse_binds(REAL).len(), blocks);
    }

    #[test]
    fn categories_come_from_the_description_prefix_in_order() {
        let categories = categories_of(&parse_binds(REAL));
        assert_eq!(categories.first().map(String::as_str), Some("Shell"));
        let mut sorted = categories.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(sorted.len(), categories.len());
    }

    #[test]
    fn an_empty_reply_yields_nothing_and_unknown_fields_are_dropped() {
        assert!(parse_binds("").is_empty());

        let binds = parse_binds("bind\n\tmodmask: 64\n\tnewfield: whatever\n\tkey: K\n");
        assert_eq!(binds.len(), 1);
        assert_eq!(binds[0].key, "K");
        assert_eq!(binds[0].modmask, 64);
    }
}
