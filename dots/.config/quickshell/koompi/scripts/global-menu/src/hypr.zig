// Hyprland IPC: the focus event stream and the active-window query.

const std = @import("std");
const linux = std.os.linux;

pub const ActiveWindow = struct {
    pid: i64 = 0,
    xwayland: bool = false,
    class: []const u8 = "",
    address: []const u8 = "",
};

pub const Session = struct {
    runtime_dir: []const u8,
    signature: []const u8,
};

fn socketPath(gpa: std.mem.Allocator, session: Session, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s}/hypr/{s}/{s}", .{ session.runtime_dir, session.signature, name });
}

pub fn connectEvents(gpa: std.mem.Allocator, session: Session) !linux.fd_t {
    const path = try socketPath(gpa, session, ".socket2.sock");
    defer gpa.free(path);
    return connectUnix(path);
}

/// Asks Hyprland for the focused window over its request socket. Spawning
/// hyprctl on every focus change would cost a process; this is the same wire.
pub fn activeWindow(gpa: std.mem.Allocator, session: Session) !std.json.Parsed(ActiveWindow) {
    const path = try socketPath(gpa, session, ".socket.sock");
    defer gpa.free(path);

    const fd = try connectUnix(path);
    defer _ = linux.close(fd);

    const req = "j/activewindow";
    if (writeAll(fd, req) == false) return error.RequestFailed;

    var body: std.ArrayListUnmanaged(u8) = .empty;
    defer body.deinit(gpa);
    var buf: [4096]u8 = undefined;
    while (true) {
        const rc = linux.read(fd, &buf, buf.len);
        if (@as(isize, @bitCast(rc)) <= 0) break;
        try body.appendSlice(gpa, buf[0..@intCast(rc)]);
        if (body.items.len > 1 << 20) break;
    }

    // alloc_always: the reply buffer dies with this function, and the caller
    // keeps using the window class out of the parsed value.
    return std.json.parseFromSlice(ActiveWindow, gpa, body.items, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

fn writeAll(fd: linux.fd_t, bytes: []const u8) bool {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = linux.write(fd, bytes.ptr + off, bytes.len - off);
        const n: isize = @bitCast(rc);
        if (n <= 0) return false;
        off += @intCast(n);
    }
    return true;
}

pub fn connectUnix(path: []const u8) !linux.fd_t {
    if (path.len >= 108) return error.PathTooLong;
    const rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM, 0);
    if (linux.errno(rc) != .SUCCESS) return error.SocketCreate;
    const fd: linux.fd_t = @intCast(rc);

    var addr: linux.sockaddr.un = .{ .path = undefined };
    addr.family = linux.AF.UNIX;
    @memcpy(addr.path[0..path.len], path);
    addr.path[path.len] = 0;

    if (linux.errno(linux.connect(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.un))) != .SUCCESS) {
        _ = linux.close(fd);
        return error.SocketConnect;
    }
    return fd;
}

/// True when the line is one of the events that can change which menu the bar
/// should be showing.
pub fn isFocusEvent(line: []const u8) bool {
    const events = [_][]const u8{
        "activewindow>>",
        "activewindowv2>>",
        "closewindow>>",
        "focusedmon>>",
        "workspace>>",
    };
    for (events) |e| {
        if (std.mem.startsWith(u8, line, e)) return true;
    }
    return false;
}

test "isFocusEvent picks the events that move focus" {
    try std.testing.expect(isFocusEvent("activewindow>>kitty,zsh"));
    try std.testing.expect(isFocusEvent("activewindowv2>>55aa"));
    try std.testing.expect(isFocusEvent("closewindow>>55aa"));
    try std.testing.expect(!isFocusEvent("createworkspace>>2"));
    try std.testing.expect(!isFocusEvent("monitoradded>>DP-1"));
}
