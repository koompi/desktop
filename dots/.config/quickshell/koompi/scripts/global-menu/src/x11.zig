// XWayland window properties, read through xprop.
//
// Only XWayland windows need this, and only when the application publishes its
// menu the GTK way (window properties) rather than through the registrar. The
// parsing is kept separate from the process spawning so it can be tested
// against captured xprop output.

const std = @import("std");

pub const Props = struct {
    bus: ?[]const u8 = null,
    menu_path: ?[]const u8 = null,
    app_path: ?[]const u8 = null,
    win_path: ?[]const u8 = null,
    unity_path: ?[]const u8 = null,
    /// KDE applications advertise a dbusmenu here instead of registering.
    kde_bus: ?[]const u8 = null,
    kde_menu_path: ?[]const u8 = null,

    pub fn complete(self: Props) bool {
        return self.bus != null and self.menu_path != null;
    }

    pub fn hasKdeMenu(self: Props) bool {
        return self.kde_bus != null and self.kde_menu_path != null;
    }
};

pub const queried = [_][]const u8{
    "_GTK_UNIQUE_BUS_NAME",
    "_GTK_MENUBAR_OBJECT_PATH",
    "_GTK_APPLICATION_OBJECT_PATH",
    "_GTK_WINDOW_OBJECT_PATH",
    "_UNITY_OBJECT_PATH",
    "_KDE_NET_WM_APPMENU_SERVICE_NAME",
    "_KDE_NET_WM_APPMENU_OBJECT_PATH",
};

/// Slices point into `stdout`.
pub fn parseProps(stdout: []const u8) Props {
    var props = Props{};
    var lines = std.mem.splitScalar(u8, stdout, '\n');
    while (lines.next()) |line| {
        if (quotedValue(line, "_GTK_UNIQUE_BUS_NAME")) |v| {
            props.bus = v;
        } else if (quotedValue(line, "_GTK_MENUBAR_OBJECT_PATH")) |v| {
            props.menu_path = v;
        } else if (quotedValue(line, "_GTK_APPLICATION_OBJECT_PATH")) |v| {
            props.app_path = v;
        } else if (quotedValue(line, "_GTK_WINDOW_OBJECT_PATH")) |v| {
            props.win_path = v;
        } else if (quotedValue(line, "_UNITY_OBJECT_PATH")) |v| {
            props.unity_path = v;
        } else if (quotedValue(line, "_KDE_NET_WM_APPMENU_SERVICE_NAME")) |v| {
            props.kde_bus = v;
        } else if (quotedValue(line, "_KDE_NET_WM_APPMENU_OBJECT_PATH")) |v| {
            props.kde_menu_path = v;
        }
    }
    return props;
}

fn quotedValue(line: []const u8, prop: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, prop)) return null;
    const q1 = std.mem.indexOfScalar(u8, line, '"') orelse return null;
    const q2 = std.mem.lastIndexOfScalar(u8, line, '"') orelse return null;
    if (q1 >= q2) return null;
    const value = line[q1 + 1 .. q2];
    if (value.len == 0) return null;
    return value;
}

pub fn parseActiveWindowId(stdout: []const u8) ?u32 {
    const marker = "window id # ";
    const idx = std.mem.indexOf(u8, stdout, marker) orelse return null;
    const hex = std.mem.trim(u8, stdout[idx + marker.len ..], " \n\r\t");
    // Multiple ids can be listed; the first is the active one.
    const first = if (std.mem.indexOfScalar(u8, hex, ',')) |c| hex[0..c] else hex;
    return std.fmt.parseInt(u32, std.mem.trim(u8, first, " \n\r\t"), 0) catch null;
}

test "parseProps reads the GTK menu properties" {
    const out =
        \\_GTK_UNIQUE_BUS_NAME(UTF8_STRING) = ":1.42"
        \\_GTK_MENUBAR_OBJECT_PATH(UTF8_STRING) = "/org/example/App/menus/menubar"
        \\_GTK_APPLICATION_OBJECT_PATH(UTF8_STRING) = "/org/example/App"
        \\_GTK_WINDOW_OBJECT_PATH(UTF8_STRING) = "/org/example/App/window/1"
        \\_UNITY_OBJECT_PATH:  not found.
        \\
    ;
    const p = parseProps(out);
    try std.testing.expect(p.complete());
    try std.testing.expectEqualStrings(":1.42", p.bus.?);
    try std.testing.expectEqualStrings("/org/example/App/menus/menubar", p.menu_path.?);
    try std.testing.expectEqualStrings("/org/example/App", p.app_path.?);
    try std.testing.expectEqualStrings("/org/example/App/window/1", p.win_path.?);
    try std.testing.expect(p.unity_path == null);
}

test "parseProps reads the KDE appmenu properties" {
    const out =
        \\_KDE_NET_WM_APPMENU_SERVICE_NAME(UTF8_STRING) = ":1.77"
        \\_KDE_NET_WM_APPMENU_OBJECT_PATH(UTF8_STRING) = "/MenuBar/1"
        \\
    ;
    const p = parseProps(out);
    try std.testing.expect(p.hasKdeMenu());
    try std.testing.expect(!p.complete());
    try std.testing.expectEqualStrings(":1.77", p.kde_bus.?);
    try std.testing.expectEqualStrings("/MenuBar/1", p.kde_menu_path.?);
}

test "parseProps treats an empty property as absent" {
    const p = parseProps("_GTK_UNIQUE_BUS_NAME(UTF8_STRING) = \"\"\n");
    try std.testing.expect(!p.complete());
}

test "parseActiveWindowId reads the root property" {
    const out = "_NET_ACTIVE_WINDOW(WINDOW): window id # 0x2400007\n";
    try std.testing.expectEqual(@as(u32, 0x2400007), parseActiveWindowId(out).?);
    try std.testing.expect(parseActiveWindowId("_NET_ACTIVE_WINDOW:  not found.\n") == null);
}
