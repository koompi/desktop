// com.canonical.AppMenu.Registrar, served by us.
//
// This is the piece that was missing. Toolkits do not push their menus at a
// panel; they wait for something to own this name and then call
// RegisterWindow(windowId, menuObjectPath) on it. With nobody owning it,
// libdbusmenu-qt, plasma-integration and appmenu-gtk-module all quietly keep
// their menubars inside the window, which is why the bar looked empty for
// every application that was not an XWayland GTK app.

const std = @import("std");
const linux = std.os.linux;
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
    /// Whether we actually hold the well-known name. Exporting the object
    /// succeeds even when the name went to somebody else, so this is the only
    /// thing that says whether our table is the one the session is using.
    ///
    /// It gates the mirror, and nothing else. RegisterWindow deliberately still
    /// answers when it is false: an application registers exactly once, on the
    /// first NameOwnerChanged that says somebody owns the name, and never
    /// retries. Refusing it because our own name_acquired callback has not been
    /// dispatched yet would cost that application its menu for its whole
    /// lifetime. Accepting one costs nothing, because a daemon that does not own
    /// the name receives no queries and no longer writes the mirror.
    owns_name: bool = false,
    /// Where the table is mirrored so it survives our own restart.
    runtime_dir: ?[]const u8 = null,
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

    // ── Surviving our own restart ─────────────────────────────────────────
    //
    // Registrations live in this process's memory, but an application only
    // registers once, when it first sees somebody own the name. Kill the daemon
    // and every menu it knew about is gone until each application is restarted,
    // which is not something a user should ever have to do.
    //
    // A D-Bus unique name outlives us: ':1.124' still addresses the same
    // connection after we respawn. So the table is mirrored to the runtime
    // directory and re-validated against the bus on startup, which recovers
    // exactly the applications that are still running. The runtime directory is
    // the right home for it: unique names are meaningless in the next session,
    // and it is cleared for us.

    fn cachePath(self: *Registrar) ?[:0]u8 {
        const dir = self.runtime_dir orelse return null;
        return std.fmt.allocPrintSentinel(self.gpa, "{s}/koompi-global-menu.registry", .{dir}, 0) catch null;
    }

    fn persist(self: *Registrar) void {
        // The mirror belongs to whoever holds the name. A displaced daemon still
        // receives NameOwnerChanged, and still has a table it built while it was
        // the owner, so without this it would write that stale table over the new
        // owner's mirror and cost it every registration it had recovered.
        if (!self.owns_name) return;

        const path = self.cachePath() orelse return;
        defer self.gpa.free(path);
        const tmp = std.fmt.allocPrintSentinel(self.gpa, "{s}.new", .{path}, 0) catch return;
        defer self.gpa.free(tmp);

        var out = std.Io.Writer.Allocating.init(self.gpa);
        defer out.deinit();
        for (self.entries.items) |e| {
            out.writer.print("{d}\t{s}\t{s}\n", .{ e.window_id, e.service, e.path }) catch return;
        }
        const bytes = out.written();

        const rc = linux.create(tmp.ptr, 0o600);
        if (linux.errno(rc) != .SUCCESS) return;
        const fd: linux.fd_t = @intCast(rc);

        var complete = true;
        var off: usize = 0;
        while (off < bytes.len) {
            const n: isize = @bitCast(linux.write(fd, bytes.ptr + off, bytes.len - off));
            if (n <= 0) {
                complete = false;
                break;
            }
            off += @intCast(n);
        }
        _ = linux.close(fd);

        // Only a whole file is moved into place. Writing over the mirror directly
        // means a daemon killed mid-write leaves a truncated one behind, and the
        // next daemon recovers whatever survived the truncation.
        if (complete and linux.errno(linux.rename(tmp.ptr, path.ptr)) == .SUCCESS) return;
        _ = linux.unlink(tmp.ptr);
    }

    /// True when `service` still has a connection on the bus. An entry whose
    /// application has exited must not come back from the cache.
    fn hasOwner(self: *Registrar, service: [:0]const u8) bool {
        const params = gio.newTuple(&.{gio.g_variant_new_string(service)});
        const reply = gio.callSync(
            self.conn,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "NameHasOwner",
            params,
            2000,
        ) orelse return false;
        defer gio.g_variant_unref(reply);
        if (gio.g_variant_n_children(reply) == 0) return false;
        const v = gio.child(reply, 0);
        defer gio.g_variant_unref(v);
        return gio.g_variant_get_boolean(v) != 0;
    }

    /// Reloads the mirrored table, dropping anything whose application has gone.
    /// Returns the number of entries recovered.
    pub fn restore(self: *Registrar) usize {
        const path = self.cachePath() orelse return 0;
        defer self.gpa.free(path);

        const rc = linux.open(path.ptr, .{ .ACCMODE = .RDONLY }, 0);
        if (linux.errno(rc) != .SUCCESS) return 0;
        const fd: linux.fd_t = @intCast(rc);
        defer _ = linux.close(fd);

        var body: std.ArrayListUnmanaged(u8) = .empty;
        defer body.deinit(self.gpa);
        var chunk: [4096]u8 = undefined;
        while (true) {
            const n: isize = @bitCast(linux.read(fd, &chunk, chunk.len));
            if (n <= 0) break;
            body.appendSlice(self.gpa, chunk[0..@intCast(n)]) catch return 0;
            if (body.items.len > 1 << 20) break;
        }

        var recovered: usize = 0;
        var lines = std.mem.tokenizeScalar(u8, body.items, '\n');
        while (lines.next()) |line| {
            var field = std.mem.splitScalar(u8, line, '\t');
            const id_str = field.next() orelse continue;
            const service = field.next() orelse continue;
            const obj_path = field.next() orelse continue;
            const window_id = std.fmt.parseInt(u32, id_str, 10) catch continue;

            const svc = self.gpa.dupeZ(u8, service) catch continue;
            if (!self.hasOwner(svc)) {
                self.gpa.free(svc);
                continue;
            }
            const p = self.gpa.dupeZ(u8, obj_path) catch {
                self.gpa.free(svc);
                continue;
            };
            // We may already know this window. ALLOW_REPLACEMENT means the name
            // can be taken from us and handed back when the daemon that took it
            // exits, and each acquisition restores, so appending blindly would
            // duplicate every entry we still hold. The mirror wins: it was
            // written by the owner that displaced us, so it is the newer view.
            _ = self.dropWindow(window_id);
            self.serial += 1;
            self.entries.append(self.gpa, .{
                .window_id = window_id,
                .service = svc,
                .path = p,
                .pid = self.pidOf(svc),
                .serial = self.serial,
            }) catch {
                self.gpa.free(svc);
                self.gpa.free(p);
                continue;
            };
            recovered += 1;
        }
        // Drop the ones that did not survive, so the file does not grow forever.
        self.persist();
        return recovered;
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
        _ = self.dropWindow(window_id); // one mirror write for the whole change

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
        self.persist();
        self.notify();
    }

    /// Forgets every entry for `window_id`, without mirroring the result: callers
    /// that are mid-rebuild persist once at the end instead.
    fn dropWindow(self: *Registrar, window_id: u32) bool {
        var i: usize = 0;
        var removed = false;
        while (i < self.entries.items.len) {
            if (self.entries.items[i].window_id == window_id) {
                const e = self.entries.swapRemove(i);
                self.gpa.free(e.service);
                self.gpa.free(e.path);
                removed = true;
            } else i += 1;
        }
        return removed;
    }

    fn removeWindow(self: *Registrar, window_id: u32) void {
        if (self.dropWindow(window_id)) self.persist();
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
        if (removed) {
            self.persist();
            self.notify();
        }
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

fn onNameAcquired(_: *gio.Connection, _: [*:0]const u8, user_data: ?*anyopaque) callconv(.c) void {
    const self: *Registrar = @ptrCast(@alignCast(user_data.?));
    self.owns_name = true;
    // Owning the name is the point at which our answers start mattering, so it
    // is where the previous daemon's table is reclaimed. Applications that are
    // still running keep their menus without being restarted; ones that exited
    // while we were gone are dropped by the bus check inside restore().
    if (self.restore() > 0) {
        const msg = "global-menu: recovered registrations from the previous daemon\n";
        _ = std.os.linux.write(2, msg.ptr, msg.len);
    }
    self.notify();
}

fn onNameLost(_: *gio.Connection, _: [*:0]const u8, user_data: ?*anyopaque) callconv(.c) void {
    const self: *Registrar = @ptrCast(@alignCast(user_data.?));
    self.owns_name = false;
    const msg = "global-menu: lost com.canonical.AppMenu.Registrar to another owner\n";
    _ = std.os.linux.write(2, msg.ptr, msg.len);
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

    // REPLACE so a respawned daemon takes the name back from a stale owner
    // instead of queueing behind it forever, and ALLOW_REPLACEMENT so the next
    // one can do the same to us. Without both, a daemon restart leaves every
    // application registered with a process that is gone.
    _ = gio.g_bus_own_name_on_connection(
        self.conn,
        bus_name,
        gio.NAME_OWNER_FLAGS_ALLOW_REPLACEMENT | gio.NAME_OWNER_FLAGS_REPLACE,
        onNameAcquired,
        onNameLost,
        self,
        null,
    );
    return true;
}
