// com.canonical.dbusmenu client.
//
// This is the protocol Unity introduced and KDE still speaks: the application
// exports its real menubar as a tree of numbered nodes, the panel asks for the
// layout, and a click travels back as Event(id, "clicked", ...). Qt/KDE apps
// reach it through libdbusmenu-qt / plasma-integration; GTK apps reach it
// through appmenu-gtk-module. Both find the panel through the AppMenu
// registrar (see registrar.zig).

const std = @import("std");
const gio = @import("gio.zig");
const menu = @import("menu.zig");

pub const Source = struct {
    bus: [:0]const u8,
    path: [:0]const u8,

    pub fn deinit(self: *Source, gpa: std.mem.Allocator) void {
        gpa.free(self.bus);
        gpa.free(self.path);
    }

    pub fn dupe(self: Source, gpa: std.mem.Allocator) !Source {
        return .{
            .bus = try gpa.dupeZ(u8, self.bus),
            .path = try gpa.dupeZ(u8, self.path),
        };
    }
};

const max_depth = 8;

const Fetcher = struct {
    gpa: std.mem.Allocator,
    conn: *gio.Connection,
    src: Source,
    table: *menu.Table,

    /// Parses one (ia{sv}av) node into an item plus its children.
    fn node(self: *Fetcher, n: *gio.Variant, depth: usize) error{OutOfMemory}!?menu.Item {
        if (gio.g_variant_n_children(n) < 3) return null;

        const id_var = gio.child(n, 0);
        defer gio.g_variant_unref(id_var);
        const props = gio.child(n, 1);
        defer gio.g_variant_unref(props);
        const kids = gio.child(n, 2);
        defer gio.g_variant_unref(kids);

        const item_id = gio.g_variant_get_int32(id_var);

        if (boolProp(props, "visible", true) == false) return null;

        var label: []u8 = if (gio.dictLookup(props, "label")) |lv| blk: {
            defer gio.g_variant_unref(lv);
            if (!gio.isType(lv, "s")) break :blk try self.gpa.dupe(u8, "");
            break :blk try menu.stripMnemonics(self.gpa, gio.str(lv));
        } else try self.gpa.dupe(u8, "");
        errdefer self.gpa.free(label);

        var shortcut = try self.shortcutOf(props);
        errdefer self.gpa.free(shortcut);

        var item = menu.Item{
            .label = label,
            .shortcut = shortcut,
            .enabled = boolProp(props, "enabled", true),
        };
        label = &.{};
        shortcut = &.{};

        if (gio.dictLookup(props, "type")) |tv| {
            defer gio.g_variant_unref(tv);
            if (gio.isType(tv, "s") and std.mem.eql(u8, gio.str(tv), "separator")) {
                item.separator = true;
                item.enabled = false;
            }
        }

        // Qt only fills a submenu in on AboutToShow, so "children-display" is
        // the only sign that an item opens one until the user does.
        if (gio.dictLookup(props, "children-display")) |cv| {
            defer gio.g_variant_unref(cv);
            if (gio.isType(cv, "s") and std.mem.eql(u8, gio.str(cv), "submenu")) item.submenu = true;
        }

        if (gio.dictLookup(props, "toggle-type")) |tv| {
            defer gio.g_variant_unref(tv);
            if (gio.isType(tv, "s") and gio.str(tv).len > 0) {
                item.toggle = true;
                if (gio.dictLookup(props, "toggle-state")) |sv| {
                    defer gio.g_variant_unref(sv);
                    if (gio.isType(sv, "i")) item.checked = gio.g_variant_get_int32(sv) == 1;
                }
            }
        }

        if (!item.separator) {
            item.id = try self.table.add(.{ .dbusmenu = .{
                .bus = try self.gpa.dupe(u8, self.src.bus),
                .path = try self.gpa.dupe(u8, self.src.path),
                .item_id = item_id,
            } });
        }

        if (depth < max_depth) {
            item.children = try self.childList(kids, depth + 1);
        }
        return item;
    }

    fn childList(self: *Fetcher, kids: *gio.Variant, depth: usize) error{OutOfMemory}![]menu.Item {
        var out: std.ArrayListUnmanaged(menu.Item) = .empty;
        errdefer {
            for (out.items) |*it| it.deinit(self.gpa);
            out.deinit(self.gpa);
        }
        var i: usize = 0;
        while (i < gio.g_variant_n_children(kids)) : (i += 1) {
            const boxed = gio.child(kids, i);
            defer gio.g_variant_unref(boxed);
            const inner = gio.unbox(boxed);
            defer gio.g_variant_unref(inner);
            if (try self.node(inner, depth)) |item| try out.append(self.gpa, item);
        }
        return out.toOwnedSlice(self.gpa);
    }

    fn shortcutOf(self: *Fetcher, props: *gio.Variant) ![]u8 {
        const sv = gio.dictLookup(props, "shortcut") orelse return self.gpa.dupe(u8, "");
        defer gio.g_variant_unref(sv);
        // aas: a list of key sequences; the menu shows the first.
        if (gio.g_variant_n_children(sv) == 0) return self.gpa.dupe(u8, "");
        const seq = gio.child(sv, 0);
        defer gio.g_variant_unref(seq);

        var out: std.ArrayListUnmanaged(u8) = .empty;
        errdefer out.deinit(self.gpa);
        var i: usize = 0;
        while (i < gio.g_variant_n_children(seq)) : (i += 1) {
            const part = gio.child(seq, i);
            defer gio.g_variant_unref(part);
            if (!gio.isType(part, "s")) continue;
            if (out.items.len > 0) try out.append(self.gpa, '+');
            const s = gio.str(part);
            if (std.ascii.eqlIgnoreCase(s, "control")) {
                try out.appendSlice(self.gpa, "Ctrl");
            } else if (s.len == 1) {
                try out.append(self.gpa, std.ascii.toUpper(s[0]));
            } else {
                try out.appendSlice(self.gpa, s);
            }
        }
        return out.toOwnedSlice(self.gpa);
    }
};

fn boolProp(props: *gio.Variant, name: [*:0]const u8, default: bool) bool {
    const v = gio.dictLookup(props, name) orelse return default;
    defer gio.g_variant_unref(v);
    if (!gio.isType(v, "b")) return default;
    return gio.g_variant_get_boolean(v) != 0;
}

const wanted_props = [_][]const u8{
    "label",           "enabled", "visible", "type",
    "children-display", "toggle-type", "toggle-state", "shortcut",
};

/// GetLayout on `parent`, returning the parsed children.
pub fn fetchFrom(
    gpa: std.mem.Allocator,
    conn: *gio.Connection,
    src: Source,
    table: *menu.Table,
    parent: i32,
) ![]menu.Item {
    // Ask the app to populate the subtree first. Qt apps build menus lazily and
    // only settle their enabled states here.
    aboutToShow(conn, src, parent);

    var prop_vars: [wanted_props.len]*gio.Variant = undefined;
    for (wanted_props, 0..) |p, i| {
        var buf: [32]u8 = undefined;
        @memcpy(buf[0..p.len], p);
        buf[p.len] = 0;
        prop_vars[i] = gio.g_variant_new_string(buf[0..p.len :0]);
    }
    const params = gio.newTuple(&.{
        gio.g_variant_new_int32(parent),
        gio.g_variant_new_int32(-1),
        gio.newStringArray(&prop_vars),
    });

    const reply = gio.callSync(conn, src.bus, src.path, "com.canonical.dbusmenu", "GetLayout", params, 3000) orelse
        return gpa.alloc(menu.Item, 0);
    defer gio.g_variant_unref(reply);
    if (gio.g_variant_n_children(reply) < 2) return gpa.alloc(menu.Item, 0);

    const root = gio.child(reply, 1);
    defer gio.g_variant_unref(root);
    if (gio.g_variant_n_children(root) < 3) return gpa.alloc(menu.Item, 0);

    const kids = gio.child(root, 2);
    defer gio.g_variant_unref(kids);

    var f = Fetcher{ .gpa = gpa, .conn = conn, .src = src, .table = table };
    return menu.tidy(gpa, try f.childList(kids, 0));
}

pub fn fetch(gpa: std.mem.Allocator, conn: *gio.Connection, src: Source, table: *menu.Table) ![]menu.Item {
    return fetchFrom(gpa, conn, src, table, 0);
}

pub fn aboutToShow(conn: *gio.Connection, src: Source, id: i32) void {
    const params = gio.newTuple(&.{gio.g_variant_new_int32(id)});
    if (gio.callSync(conn, src.bus, src.path, "com.canonical.dbusmenu", "AboutToShow", params, 2000)) |r| {
        gio.g_variant_unref(r);
    }
}

/// Sends a dbusmenu event. `kind` is "clicked", "opened" or "closed".
pub fn event(conn: *gio.Connection, bus: [:0]const u8, path: [:0]const u8, id: i32, kind: [*:0]const u8) void {
    const params = gio.newTuple(&.{
        gio.g_variant_new_int32(id),
        gio.g_variant_new_string(kind),
        gio.g_variant_new_variant(gio.g_variant_new_int32(0)),
        gio.g_variant_new_uint32(0),
    });
    if (gio.callSync(conn, bus, path, "com.canonical.dbusmenu", "Event", params, 3000)) |r| {
        gio.g_variant_unref(r);
    }
}
