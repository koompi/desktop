// com.canonical.AppMenu.Registrar, served by us.
//
// This is the piece that was missing. Toolkits do not push their menus at a
// panel; they wait for something to own this name and then call
// RegisterWindow(windowId, menuObjectPath) on it. With nobody owning it,
// libdbusmenu-qt, plasma-integration and appmenu-gtk-module all quietly keep
// their menubars inside the window, which is why the bar looked empty for
// every application that was not an XWayland GTK app.

const std = @import("std");
const gio = @import("gio.zig");

pub const Entry = struct {
    window_id: u32,
    service: [:0]u8,
    path: [:0]u8,
    pid: u32,
    /// Registration order, so a PID match can pick the newest window.
    serial: u64,
};

pub const Registrar = struct {
    gpa: std.mem.Allocator,
    conn: *gio.Connection,
    entries: std.ArrayListUnmanaged(Entry) = .empty,
    serial: u64 = 0,
    on_change: ?*const fn (ctx: ?*anyopaque) void = null,
    on_change_ctx: ?*anyopaque = null,

    pub fn deinit(self: *Registrar) void {
        for (self.entries.items) |e| {
            self.gpa.free(e.service);
            self.gpa.free(e.path);
        }
        self.entries.deinit(self.gpa);
    }

    pub fn forWindow(self: *Registrar, window_id: u32) ?Entry {
        for (self.entries.items) |e| {
            if (e.window_id == window_id) return e;
        }
        return null;
    }

    /// Newest registration owned by `pid`. Used for windows we cannot address
    /// by X11 id; with several windows of one process this is a guess, and the
    /// newest one is the best guess available.
    pub fn forPid(self: *Registrar, pid: u32) ?Entry {
        var best: ?Entry = null;
        for (self.entries.items) |e| {
            if (e.pid != pid) continue;
            if (best == null or e.serial > best.?.serial) best = e;
        }
        return best;
    }

    fn notify(self: *Registrar) void {
        if (self.on_change) |cb| cb(self.on_change_ctx);
    }

    fn pidOf(self: *Registrar, service: [:0]const u8) u32 {
        const params = gio.newTuple(&.{gio.g_variant_new_string(service)});
        const reply = gio.callSync(
            self.conn,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "GetConnectionUnixProcessID",
            params,
            2000,
        ) orelse return 0;
        defer gio.g_variant_unref(reply);
        if (gio.g_variant_n_children(reply) == 0) return 0;
        const v = gio.child(reply, 0);
        defer gio.g_variant_unref(v);
        return gio.g_variant_get_uint32(v);
    }

    fn register(self: *Registrar, window_id: u32, service: []const u8, path: []const u8) !void {
        self.removeWindow(window_id);
        const svc = try self.gpa.dupeZ(u8, service);
        errdefer self.gpa.free(svc);
        const p = try self.gpa.dupeZ(u8, path);
        errdefer self.gpa.free(p);
        self.serial += 1;
        try self.entries.append(self.gpa, .{
            .window_id = window_id,
            .service = svc,
            .path = p,
            .pid = self.pidOf(svc),
            .serial = self.serial,
        });
        self.notify();
    }

    fn removeWindow(self: *Registrar, window_id: u32) void {
        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (self.entries.items[i].window_id == window_id) {
                const e = self.entries.swapRemove(i);
                self.gpa.free(e.service);
                self.gpa.free(e.path);
            } else i += 1;
        }
    }

    fn removeService(self: *Registrar, service: []const u8) void {
        var removed = false;
        var i: usize = 0;
        while (i < self.entries.items.len) {
            if (std.mem.eql(u8, self.entries.items[i].service, service)) {
                const e = self.entries.swapRemove(i);
                self.gpa.free(e.service);
                self.gpa.free(e.path);
                removed = true;
            } else i += 1;
        }
        if (removed) self.notify();
    }
};

const xml =
    \\<node>
    \\  <interface name="com.canonical.AppMenu.Registrar">
    \\    <method name="RegisterWindow">
    \\      <arg type="u" name="windowId" direction="in"/>
    \\      <arg type="o" name="menuObjectPath" direction="in"/>
    \\    </method>
    \\    <method name="UnregisterWindow">
    \\      <arg type="u" name="windowId" direction="in"/>
    \\    </method>
    \\    <method name="GetMenuForWindow">
    \\      <arg type="u" name="windowId" direction="in"/>
    \\      <arg type="s" name="service" direction="out"/>
    \\      <arg type="o" name="menuObjectPath" direction="out"/>
    \\    </method>
    \\    <method name="GetMenus">
    \\      <arg type="a(uso)" name="menus" direction="out"/>
    \\    </method>
    \\    <signal name="WindowRegistered">
    \\      <arg type="u" name="windowId"/>
    \\      <arg type="s" name="service"/>
    \\      <arg type="o" name="menuObjectPath"/>
    \\    </signal>
    \\    <signal name="WindowUnregistered">
    \\      <arg type="u" name="windowId"/>
    \\    </signal>
    \\  </interface>
    \\</node>
;

const object_path = "/com/canonical/AppMenu/Registrar";
const bus_name = "com.canonical.AppMenu.Registrar";

fn onMethodCall(
    _: *gio.Connection,
    sender: [*:0]const u8,
    _: [*:0]const u8,
    _: [*:0]const u8,
    method_name: [*:0]const u8,
    parameters: *gio.Variant,
    invocation: *gio.MethodInvocation,
    user_data: ?*anyopaque,
) callconv(.c) void {
    const self: *Registrar = @ptrCast(@alignCast(user_data.?));
    const method = std.mem.span(method_name);

    if (std.mem.eql(u8, method, "RegisterWindow")) {
        const id_var = gio.child(parameters, 0);
        defer gio.g_variant_unref(id_var);
        const path_var = gio.child(parameters, 1);
        defer gio.g_variant_unref(path_var);
        self.register(gio.g_variant_get_uint32(id_var), std.mem.span(sender), gio.str(path_var)) catch {};
        gio.g_dbus_method_invocation_return_value(invocation, null);
        return;
    }

    if (std.mem.eql(u8, method, "UnregisterWindow")) {
        const id_var = gio.child(parameters, 0);
        defer gio.g_variant_unref(id_var);
        self.removeWindow(gio.g_variant_get_uint32(id_var));
        self.notify();
        gio.g_dbus_method_invocation_return_value(invocation, null);
        return;
    }

    if (std.mem.eql(u8, method, "GetMenuForWindow")) {
        const id_var = gio.child(parameters, 0);
        defer gio.g_variant_unref(id_var);
        const found = self.forWindow(gio.g_variant_get_uint32(id_var)) orelse {
            gio.g_dbus_method_invocation_return_dbus_error(
                invocation,
                "com.canonical.AppMenu.Registrar.Error.WindowNotFound",
                "window not registered",
            );
            return;
        };
        const reply = gio.newTuple(&.{
            gio.g_variant_new_string(found.service),
            gio.g_variant_new_object_path(found.path),
        });
        gio.g_dbus_method_invocation_return_value(invocation, reply);
        return;
    }

    if (std.mem.eql(u8, method, "GetMenus")) {
        var rows: std.ArrayListUnmanaged(*gio.Variant) = .empty;
        defer rows.deinit(self.gpa);
        for (self.entries.items) |e| {
            const row = gio.newTuple(&.{
                gio.g_variant_new_uint32(e.window_id),
                gio.g_variant_new_string(e.service),
                gio.g_variant_new_object_path(e.path),
            });
            rows.append(self.gpa, row) catch continue;
        }
        const t = gio.g_variant_type_new("(uso)");
        defer gio.g_variant_type_free(t);
        const arr = gio.g_variant_new_array(t, if (rows.items.len == 0) null else rows.items.ptr, rows.items.len);
        gio.g_dbus_method_invocation_return_value(invocation, gio.newTuple(&.{arr}));
        return;
    }

    gio.g_dbus_method_invocation_return_dbus_error(
        invocation,
        "org.freedesktop.DBus.Error.UnknownMethod",
        "no such method",
    );
}

fn onNameOwnerChanged(
    _: *gio.Connection,
    _: ?[*:0]const u8,
    _: [*:0]const u8,
    _: [*:0]const u8,
    _: [*:0]const u8,
    parameters: *gio.Variant,
    user_data: ?*anyopaque,
) callconv(.c) void {
    const self: *Registrar = @ptrCast(@alignCast(user_data.?));
    if (gio.g_variant_n_children(parameters) < 3) return;
    const name_var = gio.child(parameters, 0);
    defer gio.g_variant_unref(name_var);
    const new_owner = gio.child(parameters, 2);
    defer gio.g_variant_unref(new_owner);
    if (gio.str(new_owner).len != 0) return; // still alive
    self.removeService(gio.str(name_var));
}

const vtable = gio.InterfaceVTable{ .method_call = onMethodCall };

/// Publishes the registrar. Returns false if the object could not be exported;
/// losing the *name* to another registrar is not fatal, we simply consume that
/// one instead of serving our own.
pub fn publish(self: *Registrar) bool {
    var err: ?*gio.Error = null;
    const node = gio.g_dbus_node_info_new_for_xml(xml, &err) orelse {
        if (err) |e| gio.g_error_free(e);
        return false;
    };
    const iface = gio.g_dbus_node_info_lookup_interface(node, bus_name) orelse return false;

    const reg = gio.g_dbus_connection_register_object(self.conn, object_path, iface, &vtable, self, null, &err);
    if (reg == 0) {
        if (err) |e| gio.g_error_free(e);
        return false;
    }

    _ = gio.g_dbus_connection_signal_subscribe(
        self.conn,
        "org.freedesktop.DBus",
        "org.freedesktop.DBus",
        "NameOwnerChanged",
        "/org/freedesktop/DBus",
        null,
        gio.SIGNAL_FLAGS_NONE,
        onNameOwnerChanged,
        self,
        null,
    );

    _ = gio.g_bus_own_name_on_connection(self.conn, bus_name, gio.NAME_OWNER_FLAGS_NONE, null, null, null, null);
    return true;
}
