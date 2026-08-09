// The menu tree the daemon hands to the shell, plus the activation table that
// turns a click in the bar back into a D-Bus call on the owning application.
//
// The JSON is written by hand rather than derived: the shell parses key order
// nowhere, but the Zig daemon this replaces emits an exact byte sequence and the
// conformance suite diffs the two, so the order is part of the contract.

use std::fmt::Write as _;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Item {
    pub label: String,
    pub shortcut: String,
    pub enabled: bool,
    pub separator: bool,
    /// Only meaningful when `toggle` is set.
    pub checked: bool,
    pub toggle: bool,
    /// Index into the activation table, 1-based. 0 means "nothing to invoke".
    pub id: u32,
    /// The application says this item opens a submenu. Qt builds those lazily,
    /// so it is set on items that still have no children: the shell must open
    /// them, not activate them.
    pub submenu: bool,
    pub children: Vec<Item>,
}

impl Item {
    pub fn leaf(label: impl Into<String>) -> Self {
        Self {
            label: label.into(),
            enabled: true,
            ..Default::default()
        }
    }

    pub fn separator() -> Self {
        Self {
            separator: true,
            ..Default::default()
        }
    }
}

/// What to do when the shell activates or opens an item.
#[derive(Debug, Clone, PartialEq)]
pub enum Target {
    /// org.gtk.Actions on the action group that owns the prefix.
    Gtk {
        bus: String,
        path: String,
        action: String,
        /// The action target, as the application declared it.
        arg: Option<OwnedArg>,
    },
    /// com.canonical.dbusmenu on the exporting application.
    DBusMenu {
        bus: String,
        path: String,
        item_id: i32,
    },
}

/// A GTK action target. Only the shapes GTK actually puts in a menu model are
/// represented; anything else is dropped rather than guessed at, which matches
/// the Zig daemon refusing to synthesise a variant it cannot round-trip.
#[derive(Debug, Clone, PartialEq)]
pub enum OwnedArg {
    Str(String),
    I32(i32),
    U32(u32),
    Bool(bool),
    F64(f64),
}

/// Ids are handed out per payload and are only valid until the next payload,
/// which is exactly how long the shell keeps them.
#[derive(Debug, Default)]
pub struct Table {
    entries: Vec<Target>,
}

impl Table {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn clear(&mut self) {
        self.entries.clear();
    }

    pub fn add(&mut self, target: Target) -> u32 {
        self.entries.push(target);
        self.entries.len() as u32
    }

    pub fn get(&self, id: u32) -> Option<&Target> {
        if id == 0 {
            return None;
        }
        self.entries.get((id - 1) as usize)
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

/// Strips GTK/Qt mnemonic markers: "_File" -> "File", "__" -> "_".
/// Trailing "..." is kept; it is part of the label users expect to see.
pub fn strip_mnemonics(label: &str) -> String {
    let mut out = String::with_capacity(label.len());
    let bytes = label.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        let c = bytes[i];
        if (c == b'_' || c == b'&') && i + 1 < bytes.len() && bytes[i + 1] == c {
            out.push(c as char);
            i += 2;
            continue;
        }
        if c == b'_' || c == b'&' {
            // A lone marker before a letter is the mnemonic; keep the letter.
            i += 1;
            continue;
        }
        // Labels are UTF-8 and markers are ASCII, so copying the rest of a
        // multi-byte sequence verbatim is safe.
        let start = i;
        i += 1;
        while i < bytes.len() && bytes[i] & 0xC0 == 0x80 {
            i += 1;
        }
        out.push_str(&label[start..i]);
    }
    out
}

/// Turns a GTK accelerator ("<Control><Shift>s") into something a menu can
/// show ("Ctrl+Shift+S"). Unknown input is passed through unchanged.
pub fn pretty_accel(accel: &str) -> String {
    let mut out = String::new();
    let mut rest = accel;

    while rest.starts_with('<') {
        let Some(close) = rest.find('>') else { break };
        let modifier = &rest[1..close];
        let name = if modifier.eq_ignore_ascii_case("Control") || modifier.eq_ignore_ascii_case("Primary") {
            Some("Ctrl")
        } else if modifier.eq_ignore_ascii_case("Shift") {
            Some("Shift")
        } else if modifier.eq_ignore_ascii_case("Alt") || modifier.eq_ignore_ascii_case("Mod1") {
            Some("Alt")
        } else if modifier.eq_ignore_ascii_case("Super") || modifier.eq_ignore_ascii_case("Meta") {
            Some("Super")
        } else {
            None
        };
        if let Some(n) = name {
            out.push_str(n);
            out.push('+');
        }
        rest = &rest[close + 1..];
    }

    if rest.len() == 1 && rest.as_bytes()[0].is_ascii_lowercase() {
        out.push(rest.as_bytes()[0].to_ascii_uppercase() as char);
    } else {
        out.push_str(rest);
    }
    out
}

/// Drops leading, trailing and repeated separators, recursively. Applications
/// build their menus from sections and hide entries at runtime, so a menu that
/// is correct on their side routinely arrives with separators that would look
/// like mistakes in the bar.
pub fn tidy(items: Vec<Item>) -> Vec<Item> {
    let mut out: Vec<Item> = Vec::with_capacity(items.len());
    for mut item in items {
        item.children = tidy(std::mem::take(&mut item.children));
        if item.separator && out.last().is_none_or(|prev| prev.separator) {
            continue;
        }
        out.push(item);
    }
    while out.last().is_some_and(|last| last.separator) {
        out.pop();
    }
    out
}

/// One JSON object per line, short keys - this runs on every focus change. `gen`
/// names the id space; ids are handed out per payload and reused, so the shell
/// echoes it back and the daemon refuses anything from a replaced generation.
pub fn write_json(items: &[Item], generation: u32) -> String {
    let mut out = String::from("{\"items\":");
    write_array(&mut out, items);
    let _ = writeln!(out, ",\"gen\":{generation}}}");
    out
}

/// A replacement subtree for one item, answering an `open`.
pub fn write_patch_json(id: u32, items: &[Item], generation: u32) -> String {
    let mut out = String::new();
    let _ = write!(out, "{{\"patch\":{id},\"gen\":{generation},\"items\":");
    write_array(&mut out, items);
    out.push_str("}\n");
    out
}

pub fn write_array(out: &mut String, items: &[Item]) {
    out.push('[');
    for (i, item) in items.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        write_item(out, item);
    }
    out.push(']');
}

fn write_item(out: &mut String, item: &Item) {
    out.push_str("{\"label\":");
    write_string(out, &item.label);
    let _ = write!(
        out,
        ",\"id\":{},\"enabled\":{},\"sep\":{}",
        item.id, item.enabled, item.separator
    );
    if !item.shortcut.is_empty() {
        out.push_str(",\"shortcut\":");
        write_string(out, &item.shortcut);
    }
    if item.toggle {
        let _ = write!(out, ",\"toggle\":true,\"checked\":{}", item.checked);
    }
    if item.submenu || !item.children.is_empty() {
        out.push_str(",\"sub\":true");
    }
    if !item.children.is_empty() {
        out.push_str(",\"items\":");
        write_array(out, &item.children);
    }
    out.push('}');
}

fn write_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    // The cases below are lifted from src/menu.zig's own tests. They are the
    // conformance bar at unit level: the two implementations must agree here
    // before the end-to-end suite is worth running.

    #[test]
    fn strip_mnemonics_keeps_escaped_markers() {
        for (input, want) in [
            ("_File", "File"),
            ("&Edit", "Edit"),
            ("Save _As...", "Save As..."),
            ("Search __here", "Search _here"),
            ("Plain", "Plain"),
        ] {
            assert_eq!(strip_mnemonics(input), want, "input {input:?}");
        }
    }

    #[test]
    fn strip_mnemonics_survives_multibyte() {
        assert_eq!(strip_mnemonics("_Ouvrir un fichier — récent"), "Ouvrir un fichier — récent");
        assert_eq!(strip_mnemonics("បើក_ឯកសារ"), "បើកឯកសារ");
    }

    #[test]
    fn pretty_accel_renders_gtk_accelerators() {
        for (input, want) in [
            ("<Control>q", "Ctrl+Q"),
            ("<Primary><Shift>s", "Ctrl+Shift+S"),
            ("<Alt>F4", "Alt+F4"),
            ("F11", "F11"),
            ("", ""),
        ] {
            assert_eq!(pretty_accel(input), want, "input {input:?}");
        }
    }

    #[test]
    fn tidy_drops_leading_trailing_and_doubled_separators() {
        let items = vec![
            Item::separator(),
            Item::leaf("New"),
            Item::separator(),
            Item::separator(),
            Item::leaf("Quit"),
            Item::separator(),
        ];

        let out = tidy(items);

        assert_eq!(out.len(), 3);
        assert_eq!(out[0].label, "New");
        assert!(out[1].separator);
        assert_eq!(out[2].label, "Quit");
    }

    #[test]
    fn tidy_recurses_into_children() {
        let parent = Item {
            children: vec![Item::separator(), Item::leaf("Only"), Item::separator()],
            ..Item::leaf("File")
        };
        let out = tidy(vec![parent]);
        assert_eq!(out[0].children.len(), 1);
        assert_eq!(out[0].children[0].label, "Only");
    }

    #[test]
    fn write_json_emits_the_shell_wire_format() {
        let root = Item {
            id: 1,
            children: vec![Item {
                id: 2,
                shortcut: "Ctrl+Q".into(),
                ..Item::leaf("Quit \"now\"")
            }],
            ..Item::leaf("File")
        };

        assert_eq!(
            write_json(&[root], 7),
            "{\"items\":[{\"label\":\"File\",\"id\":1,\"enabled\":true,\"sep\":false,\"sub\":true,\
             \"items\":[{\"label\":\"Quit \\\"now\\\"\",\"id\":2,\"enabled\":true,\"sep\":false,\"shortcut\":\"Ctrl+Q\"}]}],\"gen\":7}\n"
        );
    }

    // The shell decides between "open <id>" and "activate <id>" from what the
    // wire format says, so a lazily built submenu that arrives with no children
    // yet has to be distinguishable from a leaf in the JSON itself.
    #[test]
    fn write_json_marks_a_childless_submenu_as_one() {
        let lazy = Item {
            id: 3,
            submenu: true,
            ..Item::leaf("Tools")
        };
        let leaf = Item {
            id: 4,
            ..Item::leaf("New")
        };

        let out = write_json(&[lazy, leaf], 1);

        assert!(out.contains("{\"label\":\"Tools\",\"id\":3,\"enabled\":true,\"sep\":false,\"sub\":true}"));
        assert!(out.contains("{\"label\":\"New\",\"id\":4,\"enabled\":true,\"sep\":false}"));
        assert!(!out.contains("\"items\":[]"));
    }

    #[test]
    fn table_hands_out_one_based_ids_and_refuses_zero() {
        let mut table = Table::new();
        let id = table.add(Target::DBusMenu {
            bus: ":1.5".into(),
            path: "/MenuBar".into(),
            item_id: 12,
        });
        assert_eq!(id, 1);
        assert!(table.get(0).is_none());
        assert!(table.get(2).is_none());
        assert!(matches!(table.get(1), Some(Target::DBusMenu { item_id: 12, .. })));
    }

    #[test]
    fn control_characters_are_escaped() {
        let item = Item::leaf("a\u{1}b\tc");
        let out = write_json(&[item], 1);
        assert!(out.contains("\"a\\u0001b\\tc\""), "{out}");
    }
}
