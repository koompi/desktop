// KOOMPI global-menu daemon.
//
// Owns com.canonical.AppMenu.Registrar, follows the Hyprland focus, resolves
// the focused window's exported menu (dbusmenu or org.gtk.Menus), and streams
// it to the shell as one JSON line per focus change. Clicks come back on
// stdin as "activate <id>" and are turned into the D-Bus call the owning
// application expects.
//
// Wire protocol, shell -> daemon (one command per line):
//   activate <id>   invoke the item
//   open <id>       tell the app a submenu is opening; may answer with a patch
//   close <id>      tell the app the submenu closed
//   refresh         re-resolve the focused window
//   gtk <bus> <menu_path> [app_path] [win_path]   (--test only)
//   dbusmenu <bus> <path>                          (--test only)
//
// daemon -> shell:
//   {"items":[...]}              the full menu for the focused window
//   {"patch":<id>,"items":[...]} replacement children for one item

const std = @import("std");
const linux = std.os.linux;

const gio = @import("gio.zig");
const menu = @import("menu.zig");
const gtkmenu = @import("gtkmenu.zig");
const dbusmenu = @import("dbusmenu.zig");
const registrar = @import("registrar.zig");
const hypr = @import("hypr.zig");
const x11 = @import("x11.zig");

const MenuSource = union(enum) {
    none,
    gtk: gtkmenu.Source,
    dbusmenu: dbusmenu.Source,

    fn deinit(self: *MenuSource, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .none => {},
            .gtk => |*s| s.deinit(gpa),
            .dbusmenu => |*s| s.deinit(gpa),
        }
        self.* = .none;
    }
};

const Daemon = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    conn: *gio.Connection,
    reg: registrar.Registrar,
    table: menu.Table,
    session: ?hypr.Session = null,
    source: MenuSource = .none,
    stdin_buf: std.ArrayListUnmanaged(u8) = .empty,
    hypr_buf: std.ArrayListUnmanaged(u8) = .empty,
    refresh_scheduled: bool = false,
    /// Set by --test: no compositor, the shell drives the source directly.
    manual: bool = false,

    // ── Output ────────────────────────────────────────────────────────────

    fn emit(self: *Daemon, items: []const menu.Item) void {
        var out = std.Io.Writer.Allocating.init(self.gpa);
        defer out.deinit();
        menu.writeJson(&out.writer, items) catch return;
        writeStdout(out.written());
    }

    fn emitPatch(self: *Daemon, id: u32, items: []const menu.Item) void {
        var out = std.Io.Writer.Allocating.init(self.gpa);
        defer out.deinit();
        const w = &out.writer;
        w.print("{{\"patch\":{d},\"items\":", .{id}) catch return;
        menu.writeArrayJson(w, items) catch return;
        w.writeAll("}\n") catch return;
        writeStdout(out.written());
    }

    fn emitEmpty(self: *Daemon) void {
        self.emit(&.{});
    }

    // ── Resolution ────────────────────────────────────────────────────────

    /// Works out where the focused window's menu lives. Order matters: a
    /// registrar registration is the application telling us directly, and beats
    /// anything we can infer.
    fn resolveSource(self: *Daemon) MenuSource {
        const session = self.session orelse return .none;
        const parsed = hypr.activeWindow(self.gpa, session) catch return .none;
        defer parsed.deinit();
        const win = parsed.value;
        if (win.pid == 0) return .none;

        var xid: ?u32 = null;
        if (win.xwayland) xid = self.x11ActiveWindowId();

        if (xid) |id| {
            if (self.reg.forWindow(id)) |e| return self.dbusmenuSource(e.service, e.path);
        }
        if (self.reg.forPid(@intCast(win.pid))) |e| return self.dbusmenuSource(e.service, e.path);
        if (xid) |id| {
            if (self.fromX11(id)) |s| return s;
        }
        if (self.gtkFromBusName(win.class, @intCast(win.pid))) |s| return s;
        return .none;
    }

    fn dbusmenuSource(self: *Daemon, service: []const u8, path: []const u8) MenuSource {
        const bus = self.gpa.dupeZ(u8, service) catch return .none;
        const p = self.gpa.dupeZ(u8, path) catch {
            self.gpa.free(bus);
            return .none;
        };
        return .{ .dbusmenu = .{ .bus = bus, .path = p } };
    }

    fn x11ActiveWindowId(self: *Daemon) ?u32 {
        const r = std.process.run(self.gpa, self.io, .{
            .argv = &.{ "xprop", "-root", "_NET_ACTIVE_WINDOW" },
            .stdout_limit = std.Io.Limit.limited(512),
        }) catch return null;
        defer self.gpa.free(r.stdout);
        defer self.gpa.free(r.stderr);
        return x11.parseActiveWindowId(r.stdout);
    }

    /// Reads the menu-related properties off an XWayland window. KDE
    /// applications point at a dbusmenu here rather than registering, so both
    /// conventions come out of the same xprop call.
    fn fromX11(self: *Daemon, xid: u32) ?MenuSource {
        const xid_str = std.fmt.allocPrint(self.gpa, "0x{x}", .{xid}) catch return null;
        defer self.gpa.free(xid_str);

        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(self.gpa);
        argv.appendSlice(self.gpa, &.{ "xprop", "-id", xid_str }) catch return null;
        argv.appendSlice(self.gpa, &x11.queried) catch return null;

        const r = std.process.run(self.gpa, self.io, .{
            .argv = argv.items,
            .stdout_limit = std.Io.Limit.limited(2048),
        }) catch return null;
        defer self.gpa.free(r.stdout);
        defer self.gpa.free(r.stderr);

        const props = x11.parseProps(r.stdout);
        if (props.hasKdeMenu()) return self.dbusmenuSource(props.kde_bus.?, props.kde_menu_path.?);
        if (!props.complete()) return null;

        var src = gtkmenu.Source{
            .bus = self.gpa.dupeZ(u8, props.bus.?) catch return null,
            .menu_path = self.gpa.dupeZ(u8, props.menu_path.?) catch return null,
        };
        if (props.app_path) |p| src.app_path = self.gpa.dupeZ(u8, p) catch null;
        if (props.win_path) |p| src.win_path = self.gpa.dupeZ(u8, p) catch null;
        if (props.unity_path) |p| src.unity_path = self.gpa.dupeZ(u8, p) catch null;
        return .{ .gtk = src };
    }

    /// Native-Wayland GTK applications publish no window properties, so the
    /// only handle we have is the app id. A GApplication owns its app id as a
    /// bus name and exports its menubar under the matching object path, so a
    /// window class with a dot in it is worth one probe.
    fn gtkFromBusName(self: *Daemon, class: []const u8, pid: u32) ?MenuSource {
        if (std.mem.indexOfScalar(u8, class, '.') == null) return null;
        if (class.len > 200) return null;

        const bus = self.gpa.dupeZ(u8, class) catch return null;
        var keep_bus = false;
        defer if (!keep_bus) self.gpa.free(bus);

        if (self.busNamePid(bus) != pid) return null;

        var base: std.ArrayListUnmanaged(u8) = .empty;
        defer base.deinit(self.gpa);
        base.append(self.gpa, '/') catch return null;
        for (class) |c| base.append(self.gpa, if (c == '.' or c == '-') '/' else c) catch return null;
        const base_path = base.items;

        const menu_path = std.fmt.allocPrintSentinel(self.gpa, "{s}/menus/menubar", .{base_path}, 0) catch return null;
        var keep_menu = false;
        defer if (!keep_menu) self.gpa.free(menu_path);

        if (!self.hasGtkMenu(bus, menu_path)) return null;

        var src = gtkmenu.Source{
            .bus = bus,
            .menu_path = menu_path,
            .app_path = self.gpa.dupeZ(u8, base_path) catch null,
        };
        src.win_path = self.findWindowActionPath(bus, base_path);
        keep_bus = true;
        keep_menu = true;
        return .{ .gtk = src };
    }

    fn busNamePid(self: *Daemon, name: [:0]const u8) u32 {
        const params = gio.newTuple(&.{gio.g_variant_new_string(name)});
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

    fn hasGtkMenu(self: *Daemon, bus: [:0]const u8, path: [:0]const u8) bool {
        const arr = gio.newU32Array(&.{gio.g_variant_new_uint32(0)});
        const reply = gio.callSync(self.conn, bus, path, "org.gtk.Menus", "Start", gio.newTuple(&.{arr}), 2000) orelse
            return false;
        defer gio.g_variant_unref(reply);
        if (gio.g_variant_n_children(reply) == 0) return false;
        const list = gio.child(reply, 0);
        defer gio.g_variant_unref(list);
        return gio.g_variant_n_children(list) > 0;
    }

    /// GTK exports per-window action groups at <base>/window/<n>. Nothing tells
    /// us which one belongs to the focused window, so take the first that
    /// answers; single-window applications are the common case and multi-window
    /// ones still get the right menu, only the win.* enabled states may come
    /// from a sibling window.
    fn findWindowActionPath(self: *Daemon, bus: [:0]const u8, base: []const u8) ?[:0]const u8 {
        var n: u32 = 1;
        while (n <= 4) : (n += 1) {
            const path = std.fmt.allocPrintSentinel(self.gpa, "{s}/window/{d}", .{ base, n }, 0) catch return null;
            const reply = gio.callSync(self.conn, bus, path, "org.gtk.Actions", "DescribeAll", null, 1000);
            if (reply) |r| {
                gio.g_variant_unref(r);
                return path;
            }
            self.gpa.free(path);
        }
        return null;
    }

    // ── Refresh ───────────────────────────────────────────────────────────

    fn refresh(self: *Daemon) void {
        if (!self.manual) {
            var next = self.resolveSource();
            // Focus flaps: moving between two windows of the same application,
            // or a panel taking a grab, resolves to the menu already on screen.
            // Re-emitting would tear down a menu the user has open.
            if (sameSource(self.source, next)) {
                next.deinit(self.gpa);
                return;
            }
            self.source.deinit(self.gpa);
            self.source = next;
        }
        self.publishSource();
    }

    fn publishSource(self: *Daemon) void {
        self.table.clear();
        const items: []menu.Item = switch (self.source) {
            .none => return self.emitEmpty(),
            .gtk => |s| gtkmenu.fetch(self.gpa, self.conn, s, &self.table) catch return self.emitEmpty(),
            .dbusmenu => |s| dbusmenu.fetch(self.gpa, self.conn, s, &self.table) catch return self.emitEmpty(),
        };
        defer menu.freeItems(self.gpa, items);
        self.emit(items);
    }

    fn scheduleRefresh(self: *Daemon) void {
        if (self.refresh_scheduled) return;
        self.refresh_scheduled = true;
        _ = gio.g_timeout_add(60, onRefreshTimeout, self);
    }

    // ── Commands ──────────────────────────────────────────────────────────

    fn command(self: *Daemon, line: []const u8) void {
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        const verb = it.next() orelse return;

        if (std.mem.eql(u8, verb, "activate")) {
            const id = std.fmt.parseInt(u32, it.next() orelse return, 10) catch return;
            self.activate(id);
            return;
        }
        if (std.mem.eql(u8, verb, "open") or std.mem.eql(u8, verb, "close")) {
            const id = std.fmt.parseInt(u32, it.next() orelse return, 10) catch return;
            self.setOpen(id, std.mem.eql(u8, verb, "open"));
            return;
        }
        if (std.mem.eql(u8, verb, "refresh")) {
            self.refresh();
            return;
        }
        if (self.manual and std.mem.eql(u8, verb, "gtk")) {
            const bus = it.next() orelse return;
            const menu_path = it.next() orelse return;
            var src = gtkmenu.Source{
                .bus = self.gpa.dupeZ(u8, bus) catch return,
                .menu_path = self.gpa.dupeZ(u8, menu_path) catch return,
            };
            if (it.next()) |p| src.app_path = self.gpa.dupeZ(u8, p) catch null;
            if (it.next()) |p| src.win_path = self.gpa.dupeZ(u8, p) catch null;
            self.source.deinit(self.gpa);
            self.source = .{ .gtk = src };
            self.publishSource();
            return;
        }
        if (self.manual and std.mem.eql(u8, verb, "dbusmenu")) {
            const bus = it.next() orelse return;
            const path = it.next() orelse return;
            self.source.deinit(self.gpa);
            self.source = self.dbusmenuSource(bus, path);
            self.publishSource();
            return;
        }
    }

    fn activate(self: *Daemon, id: u32) void {
        const target = self.table.get(id) orelse return;
        switch (target.*) {
            .gtk => |g| gtkmenu.activate(self.conn, g.bus, g.path, g.action, g.arg),
            .dbusmenu => |d| {
                const bus = self.gpa.dupeZ(u8, d.bus) catch return;
                defer self.gpa.free(bus);
                const path = self.gpa.dupeZ(u8, d.path) catch return;
                defer self.gpa.free(path);
                dbusmenu.event(self.conn, bus, path, d.item_id, "clicked");
            },
        }
    }

    /// Applications with lazily built menus only fill a submenu in when they
    /// are told it is about to show, so opening one re-reads that subtree and
    /// patches it into the shell's copy.
    fn setOpen(self: *Daemon, id: u32, opening: bool) void {
        const target = self.table.get(id) orelse return;
        const d = switch (target.*) {
            .dbusmenu => |d| d,
            .gtk => return,
        };
        const bus = self.gpa.dupeZ(u8, d.bus) catch return;
        defer self.gpa.free(bus);
        const path = self.gpa.dupeZ(u8, d.path) catch return;
        defer self.gpa.free(path);
        const item_id = d.item_id;

        if (!opening) {
            dbusmenu.event(self.conn, bus, path, item_id, "closed");
            return;
        }

        dbusmenu.event(self.conn, bus, path, item_id, "opened");
        const src = dbusmenu.Source{ .bus = bus, .path = path };
        const items = dbusmenu.fetchFrom(self.gpa, self.conn, src, &self.table, item_id) catch return;
        defer menu.freeItems(self.gpa, items);
        if (items.len > 0) self.emitPatch(id, items);
    }

    // ── Input plumbing ────────────────────────────────────────────────────

    fn drainLines(self: *Daemon, buf: *std.ArrayListUnmanaged(u8), comptime handler: fn (*Daemon, []const u8) void) void {
        while (std.mem.indexOfScalar(u8, buf.items, '\n')) |nl| {
            const line = buf.items[0..nl];
            handler(self, line);
            const keep = buf.items[nl + 1 ..];
            std.mem.copyForwards(u8, buf.items[0..keep.len], keep);
            buf.items.len = keep.len;
        }
    }

    fn onHyprLine(self: *Daemon, line: []const u8) void {
        if (hypr.isFocusEvent(line)) self.scheduleRefresh();
    }

    fn onStdinLine(self: *Daemon, line: []const u8) void {
        self.command(std.mem.trim(u8, line, " \r\t"));
    }
};

fn sameSource(a: MenuSource, b: MenuSource) bool {
    return switch (a) {
        .none => b == .none,
        .gtk => |x| switch (b) {
            .gtk => |y| std.mem.eql(u8, x.bus, y.bus) and std.mem.eql(u8, x.menu_path, y.menu_path),
            else => false,
        },
        .dbusmenu => |x| switch (b) {
            .dbusmenu => |y| std.mem.eql(u8, x.bus, y.bus) and std.mem.eql(u8, x.path, y.path),
            else => false,
        },
    };
}

fn onRefreshTimeout(data: ?*anyopaque) callconv(.c) c_int {
    const self: *Daemon = @ptrCast(@alignCast(data.?));
    self.refresh_scheduled = false;
    self.refresh();
    return 0; // one shot
}

fn onRegistrarChange(ctx: ?*anyopaque) void {
    const self: *Daemon = @ptrCast(@alignCast(ctx.?));
    // Applications register a moment after they take focus, so a registration
    // is a reason to look at the focused window again. With no compositor to
    // ask, there is nothing to re-resolve and an extra payload would only
    // confuse whoever is driving us.
    if (!self.manual) self.scheduleRefresh();
}

fn readInto(self: *Daemon, fd: c_int, buf: *std.ArrayListUnmanaged(u8)) bool {
    var chunk: [4096]u8 = undefined;
    const rc = linux.read(fd, &chunk, chunk.len);
    const n: isize = @bitCast(rc);
    if (n <= 0) return false;
    buf.appendSlice(self.gpa, chunk[0..@intCast(n)]) catch return true;
    return true;
}

fn onHyprReadable(fd: c_int, condition: c_int, data: ?*anyopaque) callconv(.c) c_int {
    const self: *Daemon = @ptrCast(@alignCast(data.?));
    if (condition & (gio.IO_HUP | gio.IO_ERR) != 0) return 0;
    if (!readInto(self, fd, &self.hypr_buf)) return 0;
    self.drainLines(&self.hypr_buf, Daemon.onHyprLine);
    return 1;
}

fn onStdinReadable(fd: c_int, condition: c_int, data: ?*anyopaque) callconv(.c) c_int {
    const self: *Daemon = @ptrCast(@alignCast(data.?));
    if (condition & (gio.IO_HUP | gio.IO_ERR) != 0) {
        // The shell went away; so should we.
        std.process.exit(0);
    }
    if (!readInto(self, fd, &self.stdin_buf)) std.process.exit(0);
    self.drainLines(&self.stdin_buf, Daemon.onStdinLine);
    return 1;
}

fn writeStdout(bytes: []const u8) void {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = linux.write(1, bytes.ptr + off, bytes.len - off);
        const n: isize = @bitCast(rc);
        if (n <= 0) return;
        off += @intCast(n);
    }
}

fn logLine(msg: []const u8) void {
    _ = linux.write(2, msg.ptr, msg.len);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var manual = false;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next(); // argv[0]
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--test")) manual = true;
    }

    var err: ?*gio.Error = null;
    const conn = gio.g_bus_get_sync(gio.BUS_TYPE_SESSION, null, &err) orelse {
        logLine("global-menu: no session bus\n");
        return error.NoSessionBus;
    };

    var daemon = Daemon{
        .gpa = gpa,
        .io = init.io,
        .conn = conn,
        .reg = .{ .gpa = gpa, .conn = conn },
        .table = menu.Table.init(gpa),
        .manual = manual,
    };
    daemon.reg.on_change = onRegistrarChange;
    daemon.reg.on_change_ctx = &daemon;

    if (!registrar.publish(&daemon.reg)) {
        logLine("global-menu: could not publish the AppMenu registrar\n");
    }

    if (!manual) {
        const sig = init.environ_map.get("HYPRLAND_INSTANCE_SIGNATURE") orelse {
            logLine("global-menu: HYPRLAND_INSTANCE_SIGNATURE not set\n");
            return error.NoHyprland;
        };
        daemon.session = .{
            .runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR") orelse "/run/user/1000",
            .signature = sig,
        };
        const fd = try hypr.connectEvents(gpa, daemon.session.?);
        _ = gio.g_unix_fd_add_full(gio.PRIORITY_DEFAULT, fd, gio.IO_IN | gio.IO_HUP, onHyprReadable, &daemon, null);
    }

    _ = gio.g_unix_fd_add_full(gio.PRIORITY_DEFAULT, 0, gio.IO_IN | gio.IO_HUP, onStdinReadable, &daemon, null);

    daemon.emitEmpty();
    if (!manual) daemon.scheduleRefresh();

    const loop = gio.g_main_loop_new(null, 0);
    gio.g_main_loop_run(loop);
}

test {
    _ = menu;
    _ = x11;
    _ = hypr;
    _ = gtkmenu;
}
