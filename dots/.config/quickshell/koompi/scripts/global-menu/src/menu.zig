// The menu tree the daemon hands to the shell, plus the activation table that
// turns a click in the bar back into a D-Bus call on the owning application.

const std = @import("std");
const gio = @import("gio.zig");

pub const Item = struct {
    label: []u8,
    shortcut: []u8,
    enabled: bool = true,
    separator: bool = false,
    /// Only meaningful when `toggle` is set.
    checked: bool = false,
    toggle: bool = false,
    /// Index into the activation table, 1-based. 0 means "nothing to invoke".
    id: u32 = 0,
    /// The application says this item opens a submenu. Qt builds those lazily,
    /// so it is set on items that still have no children: the shell must open
    /// them, not activate them.
    submenu: bool = false,
    children: []Item = &.{},

    pub fn deinit(self: *Item, gpa: std.mem.Allocator) void {
        gpa.free(self.label);
        gpa.free(self.shortcut);
        for (self.children) |*c| c.deinit(gpa);
        gpa.free(self.children);
    }
};

pub fn freeItems(gpa: std.mem.Allocator, items: []Item) void {
    for (items) |*it| it.deinit(gpa);
    gpa.free(items);
}

/// What to do when the shell activates or opens an item.
pub const Target = union(enum) {
    /// org.gtk.Actions on the action group that owns the prefix.
    gtk: struct {
        bus: []u8,
        path: []u8,
        action: []u8,
        /// The action target, already ref-sunk. Owned by the entry.
        arg: ?*gio.Variant,
    },
    /// com.canonical.dbusmenu on the exporting application.
    dbusmenu: struct {
        bus: []u8,
        path: []u8,
        item_id: i32,
    },

    pub fn deinit(self: *Target, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .gtk => |g| {
                gpa.free(g.bus);
                gpa.free(g.path);
                gpa.free(g.action);
                if (g.arg) |a| gio.g_variant_unref(a);
            },
            .dbusmenu => |d| {
                gpa.free(d.bus);
                gpa.free(d.path);
            },
        }
    }
};

/// Ids are handed out per payload and are only valid until the next payload,
/// which is exactly how long the shell keeps them.
pub const Table = struct {
    gpa: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(Target) = .empty,

    pub fn init(gpa: std.mem.Allocator) Table {
        return .{ .gpa = gpa };
    }

    pub fn clear(self: *Table) void {
        for (self.entries.items) |*e| e.deinit(self.gpa);
        self.entries.clearRetainingCapacity();
    }

    pub fn deinit(self: *Table) void {
        self.clear();
        self.entries.deinit(self.gpa);
    }

    pub fn add(self: *Table, target: Target) !u32 {
        try self.entries.append(self.gpa, target);
        return @intCast(self.entries.items.len);
    }

    pub fn get(self: *Table, id: u32) ?*Target {
        if (id == 0 or id > self.entries.items.len) return null;
        return &self.entries.items[id - 1];
    }
};

// ── Label handling ────────────────────────────────────────────────────────────

/// Strips GTK/Qt mnemonic markers: "_File" -> "File", "__" -> "_".
/// Trailing "..." is kept; it is part of the label users expect to see.
pub fn stripMnemonics(gpa: std.mem.Allocator, label: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < label.len) : (i += 1) {
        const c = label[i];
        if ((c == '_' or c == '&') and i + 1 < label.len and label[i + 1] == c) {
            try out.append(gpa, c);
            i += 1;
            continue;
        }
        if (c == '_' or c == '&') {
            // A lone marker before a letter is the mnemonic; keep the letter.
            continue;
        }
        try out.append(gpa, c);
    }
    return out.toOwnedSlice(gpa);
}

/// Turns a GTK accelerator ("<Control><Shift>s") into something a menu can
/// show ("Ctrl+Shift+S"). Unknown input is passed through unchanged.
pub fn prettyAccel(gpa: std.mem.Allocator, accel: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(gpa);

    var rest = accel;
    while (rest.len > 0 and rest[0] == '<') {
        const close = std.mem.indexOfScalar(u8, rest, '>') orelse break;
        const mod = rest[1..close];
        const name: ?[]const u8 =
            if (std.ascii.eqlIgnoreCase(mod, "Control") or std.ascii.eqlIgnoreCase(mod, "Primary"))
                "Ctrl"
            else if (std.ascii.eqlIgnoreCase(mod, "Shift"))
                "Shift"
            else if (std.ascii.eqlIgnoreCase(mod, "Alt") or std.ascii.eqlIgnoreCase(mod, "Mod1"))
                "Alt"
            else if (std.ascii.eqlIgnoreCase(mod, "Super") or std.ascii.eqlIgnoreCase(mod, "Meta"))
                "Super"
            else
                null;
        if (name) |n| {
            try out.appendSlice(gpa, n);
            try out.append(gpa, '+');
        }
        rest = rest[close + 1 ..];
    }

    if (rest.len == 1 and std.ascii.isLower(rest[0])) {
        try out.append(gpa, std.ascii.toUpper(rest[0]));
    } else {
        try out.appendSlice(gpa, rest);
    }
    return out.toOwnedSlice(gpa);
}

/// Drops leading, trailing and repeated separators, recursively. Applications
/// build their menus from sections and hide entries at runtime, so a menu that
/// is correct on their side routinely arrives with separators that would look
/// like mistakes in the bar.
pub fn tidy(gpa: std.mem.Allocator, items: []Item) []Item {
    var w: usize = 0;
    for (items) |entry| {
        var item = entry;
        item.children = tidy(gpa, item.children);
        if (item.separator and (w == 0 or items[w - 1].separator)) {
            item.deinit(gpa);
            continue;
        }
        items[w] = item;
        w += 1;
    }
    while (w > 0 and items[w - 1].separator) {
        w -= 1;
        items[w].deinit(gpa);
    }
    return gpa.realloc(items, w) catch items[0..w];
}

// ── Wire format ───────────────────────────────────────────────────────────────

/// The shell reads one JSON object per line. Keys are short because this runs
/// on every focus change.
pub fn writeJson(writer: *std.Io.Writer, items: []const Item) !void {
    try writer.writeAll("{\"items\":");
    try writeArrayJson(writer, items);
    try writer.writeAll("}\n");
}

pub fn writeArrayJson(writer: *std.Io.Writer, items: []const Item) std.Io.Writer.Error!void {
    try writer.writeByte('[');
    for (items, 0..) |item, i| {
        if (i > 0) try writer.writeByte(',');
        try writeItem(writer, item);
    }
    try writer.writeByte(']');
}

fn writeItem(writer: *std.Io.Writer, item: Item) std.Io.Writer.Error!void {
    try writer.writeAll("{\"label\":");
    try writeString(writer, item.label);
    try writer.print(",\"id\":{d},\"enabled\":{s},\"sep\":{s}", .{
        item.id,
        if (item.enabled) "true" else "false",
        if (item.separator) "true" else "false",
    });
    if (item.shortcut.len > 0) {
        try writer.writeAll(",\"shortcut\":");
        try writeString(writer, item.shortcut);
    }
    if (item.toggle) {
        try writer.print(",\"toggle\":true,\"checked\":{s}", .{if (item.checked) "true" else "false"});
    }
    if (item.submenu or item.children.len > 0) {
        try writer.writeAll(",\"sub\":true");
    }
    if (item.children.len > 0) {
        try writer.writeAll(",\"items\":");
        try writeArrayJson(writer, item.children);
    }
    try writer.writeByte('}');
}

fn writeString(writer: *std.Io.Writer, s: []const u8) !void {
    try writer.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => {
            if (c < 0x20) {
                try writer.print("\\u{x:0>4}", .{c});
            } else {
                try writer.writeByte(c);
            }
        },
    };
    try writer.writeByte('"');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

test "stripMnemonics keeps escaped markers" {
    const gpa = std.testing.allocator;
    const cases = [_][2][]const u8{
        .{ "_File", "File" },
        .{ "&Edit", "Edit" },
        .{ "Save _As...", "Save As..." },
        .{ "Search __here", "Search _here" },
        .{ "Plain", "Plain" },
    };
    for (cases) |c| {
        const got = try stripMnemonics(gpa, c[0]);
        defer gpa.free(got);
        try std.testing.expectEqualStrings(c[1], got);
    }
}

test "prettyAccel renders GTK accelerators" {
    const gpa = std.testing.allocator;
    const cases = [_][2][]const u8{
        .{ "<Control>q", "Ctrl+Q" },
        .{ "<Primary><Shift>s", "Ctrl+Shift+S" },
        .{ "<Alt>F4", "Alt+F4" },
        .{ "F11", "F11" },
        .{ "", "" },
    };
    for (cases) |c| {
        const got = try prettyAccel(gpa, c[0]);
        defer gpa.free(got);
        try std.testing.expectEqualStrings(c[1], got);
    }
}

test "tidy drops leading, trailing and doubled separators" {
    const gpa = std.testing.allocator;

    const items = try gpa.alloc(Item, 6);
    const labels = [_][]const u8{ "", "New", "", "", "Quit", "" };
    const seps = [_]bool{ true, false, true, true, false, true };
    for (items, labels, seps) |*item, label, sep| {
        item.* = .{
            .label = try gpa.dupe(u8, label),
            .shortcut = try gpa.dupe(u8, ""),
            .separator = sep,
        };
    }

    const out = tidy(gpa, items);
    defer freeItems(gpa, out);

    try std.testing.expectEqual(@as(usize, 3), out.len);
    try std.testing.expectEqualStrings("New", out[0].label);
    try std.testing.expect(out[1].separator);
    try std.testing.expectEqualStrings("Quit", out[2].label);
}

test "writeJson emits the shell wire format" {
    const gpa = std.testing.allocator;
    var child = Item{
        .label = try gpa.dupe(u8, "Quit \"now\""),
        .shortcut = try gpa.dupe(u8, "Ctrl+Q"),
        .id = 2,
    };
    var children = try gpa.alloc(Item, 1);
    children[0] = child;
    var root = Item{
        .label = try gpa.dupe(u8, "File"),
        .shortcut = try gpa.dupe(u8, ""),
        .id = 1,
        .children = children,
    };
    defer root.deinit(gpa);
    _ = &child;

    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try writeJson(&out.writer, &.{root});

    try std.testing.expectEqualStrings(
        "{\"items\":[{\"label\":\"File\",\"id\":1,\"enabled\":true,\"sep\":false,\"sub\":true," ++
            "\"items\":[{\"label\":\"Quit \\\"now\\\"\",\"id\":2,\"enabled\":true,\"sep\":false,\"shortcut\":\"Ctrl+Q\"}]}]}\n",
        out.written(),
    );
}

// The shell decides between "open <id>" and "activate <id>" from what the wire
// format says, so a lazily built submenu that arrives with no children yet has
// to be distinguishable from a leaf in the JSON itself.
test "writeJson marks a childless submenu as one" {
    const gpa = std.testing.allocator;
    var lazy = Item{
        .label = try gpa.dupe(u8, "Tools"),
        .shortcut = try gpa.dupe(u8, ""),
        .id = 3,
        .submenu = true,
    };
    var leaf = Item{
        .label = try gpa.dupe(u8, "New"),
        .shortcut = try gpa.dupe(u8, ""),
        .id = 4,
    };
    defer lazy.deinit(gpa);
    defer leaf.deinit(gpa);

    var out = std.Io.Writer.Allocating.init(gpa);
    defer out.deinit();
    try writeJson(&out.writer, &.{ lazy, leaf });

    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, out.written(), .{});
    defer parsed.deinit();
    const items = parsed.value.object.get("items").?.array;

    const sub = items.items[0].object;
    try std.testing.expectEqualStrings("Tools", sub.get("label").?.string);
    try std.testing.expect(sub.get("sub").?.bool);
    try std.testing.expect(sub.get("items") == null);

    try std.testing.expect(items.items[1].object.get("sub") == null);
}
