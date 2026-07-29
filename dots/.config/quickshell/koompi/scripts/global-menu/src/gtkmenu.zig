// org.gtk.Menus + org.gtk.Actions client.
//
// GTK does not hand out a menu tree. It hands out *subscriptions*: Start(au)
// returns a(uuaa{sv}) — a flat list of (group, menu, items) triples — and the
// items reference other (group, menu) pairs through the ":section" and
// ":submenu" attributes. Sections are spliced into their parent with a
// separator between them; submenus become child menus. Resolving that properly
// is the whole job, because a menubar's top-level entries are almost always
// pure section links, and treating a section as a submenu (or ignoring it)
// produces empty or duplicated menus.
//
// Item state — enabled, checkbox, radio — is not in the menu model at all. It
// comes from org.gtk.Actions.DescribeAll on the action group named by the
// action's prefix ("app." / "win." / "unity.").

const std = @import("std");
const gio = @import("gio.zig");
const menu = @import("menu.zig");

pub const Source = struct {
    bus: [:0]const u8,
    menu_path: [:0]const u8,
    app_path: ?[:0]const u8 = null,
    win_path: ?[:0]const u8 = null,
    unity_path: ?[:0]const u8 = null,

    pub fn deinit(self: *Source, gpa: std.mem.Allocator) void {
        gpa.free(self.bus);
        gpa.free(self.menu_path);
        if (self.app_path) |p| gpa.free(p);
        if (self.win_path) |p| gpa.free(p);
        if (self.unity_path) |p| gpa.free(p);
    }

    pub fn dupe(self: Source, gpa: std.mem.Allocator) !Source {
        return .{
            .bus = try gpa.dupeZ(u8, self.bus),
            .menu_path = try gpa.dupeZ(u8, self.menu_path),
            .app_path = if (self.app_path) |p| try gpa.dupeZ(u8, p) else null,
            .win_path = if (self.win_path) |p| try gpa.dupeZ(u8, p) else null,
            .unity_path = if (self.unity_path) |p| try gpa.dupeZ(u8, p) else null,
        };
    }
};

const max_depth = 8;

const ActionState = struct {
    enabled: bool,
    /// Ref-sunk current state, or null for a stateless action.
    state: ?*gio.Variant,
};

const Fetcher = struct {
    gpa: std.mem.Allocator,
    conn: *gio.Connection,
    src: Source,
    table: *menu.Table,
    /// (group << 32 | menu) -> the aa{sv} item array, ref held.
    menus: std.AutoHashMapUnmanaged(u64, *gio.Variant) = .{},
    started: std.AutoHashMapUnmanaged(u32, void) = .{},
    /// action-group path -> (bare action name -> state), ref held on states.
    /// A null map means the group did not answer DescribeAll, which is not the
    /// same as "the group has no actions": in that case we must not grey the
    /// whole menu out.
    describes: std.StringHashMapUnmanaged(?std.StringHashMapUnmanaged(ActionState)) = .{},

    fn deinit(self: *Fetcher) void {
        var mit = self.menus.valueIterator();
        while (mit.next()) |v| gio.g_variant_unref(v.*);
        self.menus.deinit(self.gpa);

        var dit = self.describes.iterator();
        while (dit.next()) |kv| {
            if (kv.value_ptr.*) |*map| {
                var ait = map.iterator();
                while (ait.next()) |akv| {
                    self.gpa.free(akv.key_ptr.*);
                    if (akv.value_ptr.state) |s| gio.g_variant_unref(s);
                }
                map.deinit(self.gpa);
            }
            self.gpa.free(kv.key_ptr.*);
        }
        self.describes.deinit(self.gpa);

        self.endSubscriptions();
        self.started.deinit(self.gpa);
    }

    fn endSubscriptions(self: *Fetcher) void {
        if (self.started.count() == 0) return;
        var handles: std.ArrayListUnmanaged(*gio.Variant) = .empty;
        defer handles.deinit(self.gpa);
        var it = self.started.keyIterator();
        while (it.next()) |g| handles.append(self.gpa, gio.g_variant_new_uint32(g.*)) catch return;
        const arr = gio.newU32Array(handles.items);
        const params = gio.newTuple(&.{arr});
        if (gio.callSync(self.conn, self.src.bus, self.src.menu_path, "org.gtk.Menus", "End", params, 500)) |r| {
            gio.g_variant_unref(r);
        }
    }

    fn key(group: u32, id: u32) u64 {
        return (@as(u64, group) << 32) | id;
    }

    /// Subscribes to a group and caches every (group, menu) it returns. A
    /// single Start reply routinely carries menus for groups we did not ask
    /// for, so everything in the reply is kept.
    fn ensureGroup(self: *Fetcher, group: u32) void {
        if (self.started.contains(group)) return;
        self.started.put(self.gpa, group, {}) catch return;

        const handle = gio.g_variant_new_uint32(group);
        const arr = gio.newU32Array(&.{handle});
        const params = gio.newTuple(&.{arr});
        const reply = gio.callSync(self.conn, self.src.bus, self.src.menu_path, "org.gtk.Menus", "Start", params, 2000) orelse return;
        defer gio.g_variant_unref(reply);

        if (gio.g_variant_n_children(reply) == 0) return;
        const list = gio.child(reply, 0);
        defer gio.g_variant_unref(list);

        var i: usize = 0;
        while (i < gio.g_variant_n_children(list)) : (i += 1) {
            const triple = gio.child(list, i);
            defer gio.g_variant_unref(triple);
            if (gio.g_variant_n_children(triple) < 3) continue;

            const g_var = gio.child(triple, 0);
            defer gio.g_variant_unref(g_var);
            const m_var = gio.child(triple, 1);
            defer gio.g_variant_unref(m_var);
            const items = gio.child(triple, 2);

            const k = key(gio.g_variant_get_uint32(g_var), gio.g_variant_get_uint32(m_var));
            const gop = self.menus.getOrPut(self.gpa, k) catch {
                gio.g_variant_unref(items);
                continue;
            };
            if (gop.found_existing) {
                gio.g_variant_unref(gop.value_ptr.*);
            }
            gop.value_ptr.* = items;
        }
    }

    fn pathForPrefix(self: *Fetcher, prefix: []const u8) ?[:0]const u8 {
        if (std.mem.eql(u8, prefix, "app")) return self.src.app_path;
        if (std.mem.eql(u8, prefix, "win")) return self.src.win_path;
        if (std.mem.eql(u8, prefix, "unity")) return self.src.unity_path;
        return null;
    }

    /// DescribeAll for an action-group path, cached. Returns null when the app
    /// does not answer, which we read as "assume everything is live".
    fn describe(self: *Fetcher, path: [:0]const u8) ?*std.StringHashMapUnmanaged(ActionState) {
        if (self.describes.getPtr(path)) |m| {
            if (m.*) |*inner| return inner;
            return null;
        }

        var map: std.StringHashMapUnmanaged(ActionState) = .{};
        const owned_path = self.gpa.dupe(u8, path) catch return null;

        const reply = gio.callSync(self.conn, self.src.bus, path, "org.gtk.Actions", "DescribeAll", null, 2000);
        if (reply == null) {
            self.describes.put(self.gpa, owned_path, null) catch self.gpa.free(owned_path);
            return null;
        }
        if (reply) |r| {
            defer gio.g_variant_unref(r);
            if (gio.g_variant_n_children(r) > 0) {
                const dict = gio.child(r, 0);
                defer gio.g_variant_unref(dict);
                var i: usize = 0;
                while (i < gio.g_variant_n_children(dict)) : (i += 1) {
                    const entry = gio.child(dict, i);
                    defer gio.g_variant_unref(entry);
                    if (gio.g_variant_n_children(entry) < 2) continue;

                    const name_var = gio.child(entry, 0);
                    defer gio.g_variant_unref(name_var);
                    const desc = gio.child(entry, 1);
                    defer gio.g_variant_unref(desc);
                    if (gio.g_variant_n_children(desc) < 3) continue;

                    const enabled_var = gio.child(desc, 0);
                    defer gio.g_variant_unref(enabled_var);
                    const state_arr = gio.child(desc, 2);
                    defer gio.g_variant_unref(state_arr);

                    var state: ?*gio.Variant = null;
                    if (gio.g_variant_n_children(state_arr) > 0) {
                        const boxed = gio.child(state_arr, 0);
                        defer gio.g_variant_unref(boxed);
                        state = gio.unbox(boxed);
                    }

                    const name_copy = self.gpa.dupe(u8, gio.str(name_var)) catch continue;
                    map.put(self.gpa, name_copy, .{
                        .enabled = gio.g_variant_get_boolean(enabled_var) != 0,
                        .state = state,
                    }) catch {
                        self.gpa.free(name_copy);
                        if (state) |s| gio.g_variant_unref(s);
                    };
                }
            }
        }

        self.describes.put(self.gpa, owned_path, map) catch {
            self.gpa.free(owned_path);
            return null;
        };
        return &(self.describes.getPtr(owned_path).?.*.?);
    }

    fn resolve(self: *Fetcher, group: u32, id: u32, depth: usize) error{OutOfMemory}![]menu.Item {
        var out: std.ArrayListUnmanaged(menu.Item) = .empty;
        errdefer {
            for (out.items) |*it| it.deinit(self.gpa);
            out.deinit(self.gpa);
        }
        if (depth >= max_depth) return out.toOwnedSlice(self.gpa);

        self.ensureGroup(group);
        const items = self.menus.get(key(group, id)) orelse return out.toOwnedSlice(self.gpa);

        var i: usize = 0;
        while (i < gio.g_variant_n_children(items)) : (i += 1) {
            const attrs = gio.child(items, i);
            defer gio.g_variant_unref(attrs);

            if (gio.dictLookup(attrs, ":section")) |sec| {
                defer gio.g_variant_unref(sec);
                const ref = pairOf(sec) orelse continue;
                const sub = try self.resolve(ref[0], ref[1], depth + 1);
                defer self.gpa.free(sub);
                if (sub.len == 0) continue;
                if (out.items.len > 0) try out.append(self.gpa, try self.separator());
                try out.appendSlice(self.gpa, sub);
                continue;
            }

            var item = try self.leaf(attrs);
            errdefer item.deinit(self.gpa);

            if (gio.dictLookup(attrs, ":submenu")) |sub| {
                defer gio.g_variant_unref(sub);
                if (pairOf(sub)) |ref| {
                    item.submenu = true;
                    item.children = try self.resolve(ref[0], ref[1], depth + 1);
                }
            }
            try out.append(self.gpa, item);
        }

        return out.toOwnedSlice(self.gpa);
    }

    fn separator(self: *Fetcher) !menu.Item {
        return .{
            .label = try self.gpa.dupe(u8, ""),
            .shortcut = try self.gpa.dupe(u8, ""),
            .separator = true,
            .enabled = false,
        };
    }

    fn leaf(self: *Fetcher, attrs: *gio.Variant) !menu.Item {
        var label: []u8 = try self.gpa.dupe(u8, "");
        errdefer self.gpa.free(label);
        if (gio.dictLookup(attrs, "label")) |lv| {
            defer gio.g_variant_unref(lv);
            if (gio.isType(lv, "s")) {
                self.gpa.free(label);
                label = try menu.stripMnemonics(self.gpa, gio.str(lv));
            }
        }

        var shortcut: []u8 = try self.gpa.dupe(u8, "");
        errdefer self.gpa.free(shortcut);
        if (gio.dictLookup(attrs, "accel")) |av| {
            defer gio.g_variant_unref(av);
            if (gio.isType(av, "s")) {
                self.gpa.free(shortcut);
                shortcut = try menu.prettyAccel(self.gpa, gio.str(av));
            }
        }

        var item = menu.Item{ .label = label, .shortcut = shortcut };

        const action_var = gio.dictLookup(attrs, "action") orelse return item;
        defer gio.g_variant_unref(action_var);
        if (!gio.isType(action_var, "s")) return item;

        const full = gio.str(action_var);
        const dot = std.mem.indexOfScalar(u8, full, '.') orelse return item;
        const group_path = self.pathForPrefix(full[0..dot]) orelse return item;
        const bare = full[dot + 1 ..];

        var target: ?*gio.Variant = null;
        if (gio.dictLookup(attrs, "target")) |tv| {
            target = tv;
        }
        errdefer if (target) |t| gio.g_variant_unref(t);

        if (self.describe(group_path)) |states| {
            if (states.get(bare)) |st| {
                item.enabled = st.enabled;
                if (st.state) |s| applyState(&item, s, target);
            } else {
                // The model advertises an action the group does not implement.
                // Showing it live would be a lie; show it greyed out.
                item.enabled = false;
            }
        }

        item.id = try self.table.add(.{ .gtk = .{
            .bus = try self.gpa.dupe(u8, self.src.bus),
            .path = try self.gpa.dupe(u8, group_path),
            .action = try self.gpa.dupe(u8, bare),
            .arg = target,
        } });
        return item;
    }
};

/// A boolean state is a checkbox; a state that matches the item's target is a
/// selected radio entry. Anything else carries no visual meaning.
fn applyState(item: *menu.Item, state: *gio.Variant, target: ?*gio.Variant) void {
    if (gio.isType(state, "b")) {
        item.toggle = true;
        item.checked = gio.g_variant_get_boolean(state) != 0;
        return;
    }
    const t = target orelse return;
    if (gio.isType(state, "s") and gio.isType(t, "s")) {
        item.toggle = true;
        item.checked = std.mem.eql(u8, gio.str(state), gio.str(t));
    }
}

fn pairOf(v: *gio.Variant) ?[2]u32 {
    if (!gio.isType(v, "(uu)")) return null;
    const a = gio.child(v, 0);
    defer gio.g_variant_unref(a);
    const b = gio.child(v, 1);
    defer gio.g_variant_unref(b);
    return .{ gio.g_variant_get_uint32(a), gio.g_variant_get_uint32(b) };
}

/// Fetches the menubar rooted at (group 0, menu 0) and fills `table` with the
/// activation targets for every actionable entry.
pub fn fetch(
    gpa: std.mem.Allocator,
    conn: *gio.Connection,
    src: Source,
    table: *menu.Table,
) ![]menu.Item {
    var f = Fetcher{ .gpa = gpa, .conn = conn, .src = src, .table = table };
    defer f.deinit();
    return menu.tidy(gpa, try f.resolve(0, 0, 0));
}

/// Invokes an action on its group.
pub fn activate(conn: *gio.Connection, bus: []const u8, path: []const u8, action: []const u8, arg: ?*gio.Variant) void {
    var bus_buf: [256]u8 = undefined;
    var path_buf: [256]u8 = undefined;
    var action_buf: [256]u8 = undefined;
    const bus_z = zeroTerm(&bus_buf, bus) orelse return;
    const path_z = zeroTerm(&path_buf, path) orelse return;
    const action_z = zeroTerm(&action_buf, action) orelse return;

    const name = gio.g_variant_new_string(action_z);
    const args = if (arg) |a| gio.newVariantArray(&.{gio.g_variant_new_variant(a)}) else gio.newVariantArray(&.{});
    const params = gio.newTuple(&.{ name, args, gio.emptyAsv() });
    if (gio.callSync(conn, bus_z, path_z, "org.gtk.Actions", "Activate", params, 3000)) |r| {
        gio.g_variant_unref(r);
    }
}

fn zeroTerm(buf: []u8, s: []const u8) ?[:0]const u8 {
    if (s.len >= buf.len) return null;
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf[0..s.len :0];
}

test "zeroTerm refuses oversized input" {
    var buf: [4]u8 = undefined;
    try std.testing.expect(zeroTerm(&buf, "abcd") == null);
    try std.testing.expectEqualStrings("abc", zeroTerm(&buf, "abc").?);
}
