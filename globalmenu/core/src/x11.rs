// XWayland window properties, read through xprop. Only needed when an application
// publishes its menu the GTK way rather than through the registrar. Parsing is kept
// out of the spawn so it can be tested against captured output.

use std::process::Command;

#[derive(Debug, Default, PartialEq)]
pub struct Props {
    pub bus: Option<String>,
    pub menu_path: Option<String>,
    pub app_path: Option<String>,
    pub win_path: Option<String>,
    pub unity_path: Option<String>,
    /// KDE applications advertise a dbusmenu here instead of registering.
    pub kde_bus: Option<String>,
    pub kde_menu_path: Option<String>,
}

impl Props {
    pub fn complete(&self) -> bool {
        self.bus.is_some() && self.menu_path.is_some()
    }

    pub fn has_kde_menu(&self) -> bool {
        self.kde_bus.is_some() && self.kde_menu_path.is_some()
    }
}

pub const QUERIED: [&str; 7] = [
    "_GTK_UNIQUE_BUS_NAME",
    "_GTK_MENUBAR_OBJECT_PATH",
    "_GTK_APPLICATION_OBJECT_PATH",
    "_GTK_WINDOW_OBJECT_PATH",
    "_UNITY_OBJECT_PATH",
    "_KDE_NET_WM_APPMENU_SERVICE_NAME",
    "_KDE_NET_WM_APPMENU_OBJECT_PATH",
];

pub fn parse_props(stdout: &str) -> Props {
    let mut props = Props::default();
    for line in stdout.lines() {
        let Some((name, value)) = quoted_value(line) else {
            continue;
        };
        let slot = match name {
            "_GTK_UNIQUE_BUS_NAME" => &mut props.bus,
            "_GTK_MENUBAR_OBJECT_PATH" => &mut props.menu_path,
            "_GTK_APPLICATION_OBJECT_PATH" => &mut props.app_path,
            "_GTK_WINDOW_OBJECT_PATH" => &mut props.win_path,
            "_UNITY_OBJECT_PATH" => &mut props.unity_path,
            "_KDE_NET_WM_APPMENU_SERVICE_NAME" => &mut props.kde_bus,
            "_KDE_NET_WM_APPMENU_OBJECT_PATH" => &mut props.kde_menu_path,
            _ => continue,
        };
        *slot = Some(value.to_owned());
    }
    props
}

fn quoted_value(line: &str) -> Option<(&str, &str)> {
    let name = QUERIED.iter().find(|p| line.starts_with(**p))?;
    let q1 = line.find('"')?;
    let q2 = line.rfind('"')?;
    if q1 >= q2 {
        return None;
    }
    let value = &line[q1 + 1..q2];
    if value.is_empty() {
        return None;
    }
    Some((name, value))
}

pub fn parse_active_window_id(stdout: &str) -> Option<u32> {
    let marker = "window id # ";
    let idx = stdout.find(marker)?;
    let hex = stdout[idx + marker.len()..].trim();
    // Multiple ids can be listed; the first is the active one.
    let first = hex.split(',').next()?.trim();
    let digits = first.strip_prefix("0x").or_else(|| first.strip_prefix("0X"));
    match digits {
        Some(d) => u32::from_str_radix(d, 16).ok(),
        None => first.parse().ok(),
    }
}

pub fn read_props(window_id: u32) -> Props {
    let mut cmd = Command::new("xprop");
    cmd.arg("-id").arg(format!("0x{window_id:x}"));
    for p in QUERIED {
        cmd.arg("-f").arg(p).arg("8u").arg("=$0\\n");
    }
    for p in QUERIED {
        cmd.arg(p);
    }
    match cmd.output() {
        Ok(out) => parse_props(&String::from_utf8_lossy(&out.stdout)),
        Err(_) => Props::default(),
    }
}

pub fn active_window_id() -> Option<u32> {
    let out = Command::new("xprop")
        .args(["-root", "_NET_ACTIVE_WINDOW"])
        .output()
        .ok()?;
    parse_active_window_id(&String::from_utf8_lossy(&out.stdout))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Same captured output as src/x11.zig's own tests.

    #[test]
    fn parse_props_reads_the_gtk_menu_properties() {
        let out = concat!(
            "_GTK_UNIQUE_BUS_NAME(UTF8_STRING) = \":1.42\"\n",
            "_GTK_MENUBAR_OBJECT_PATH(UTF8_STRING) = \"/org/example/App/menus/menubar\"\n",
            "_GTK_APPLICATION_OBJECT_PATH(UTF8_STRING) = \"/org/example/App\"\n",
            "_GTK_WINDOW_OBJECT_PATH(UTF8_STRING) = \"/org/example/App/window/1\"\n",
            "_UNITY_OBJECT_PATH:  not found.\n",
        );
        let p = parse_props(out);
        assert!(p.complete());
        assert_eq!(p.bus.as_deref(), Some(":1.42"));
        assert_eq!(p.menu_path.as_deref(), Some("/org/example/App/menus/menubar"));
        assert_eq!(p.app_path.as_deref(), Some("/org/example/App"));
        assert_eq!(p.win_path.as_deref(), Some("/org/example/App/window/1"));
        assert_eq!(p.unity_path, None);
    }

    #[test]
    fn parse_props_reads_the_kde_appmenu_properties() {
        let out = concat!(
            "_KDE_NET_WM_APPMENU_SERVICE_NAME(UTF8_STRING) = \":1.77\"\n",
            "_KDE_NET_WM_APPMENU_OBJECT_PATH(UTF8_STRING) = \"/MenuBar/1\"\n",
        );
        let p = parse_props(out);
        assert!(p.has_kde_menu());
        assert!(!p.complete());
        assert_eq!(p.kde_bus.as_deref(), Some(":1.77"));
        assert_eq!(p.kde_menu_path.as_deref(), Some("/MenuBar/1"));
    }

    #[test]
    fn parse_props_treats_an_empty_property_as_absent() {
        let p = parse_props("_GTK_UNIQUE_BUS_NAME(UTF8_STRING) = \"\"\n");
        assert!(!p.complete());
    }

    #[test]
    fn parse_active_window_id_reads_the_root_property() {
        let out = "_NET_ACTIVE_WINDOW(WINDOW): window id # 0x2400007\n";
        assert_eq!(parse_active_window_id(out), Some(0x2400007));
        assert_eq!(parse_active_window_id("_NET_ACTIVE_WINDOW:  not found.\n"), None);
    }

    // xprop lists every id it finds; taking the second is a different window.
    #[test]
    fn parse_active_window_id_takes_the_first_of_several() {
        let out = "_NET_CLIENT_LIST(WINDOW): window id # 0x2400007, 0x2600009\n";
        assert_eq!(parse_active_window_id(out), Some(0x2400007));
    }
}
