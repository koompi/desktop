const std = @import("std");

const stdin_fd: std.c.fd_t = std.c.STDIN_FILENO;
const stdout_fd: std.c.fd_t = std.c.STDOUT_FILENO;

// Copied from audiod/src/emit.zig: same NDJSON-over-stdio transport, same
// framing rules. searchd is single-threaded (no PipeWire loop thread to race
// against), so the mutex here is unused contention insurance, not a
// requirement — kept for a straight diff against the original.
pub const Emitter = struct {
    gpa: std.mem.Allocator,
    fd: std.c.fd_t = stdout_fd,
    mutex: std.c.pthread_mutex_t = .{},

    pub fn line(self: *Emitter, message: anytype) void {
        const json = std.json.Stringify.valueAlloc(self.gpa, message, .{}) catch return;
        defer self.gpa.free(json);

        _ = std.c.pthread_mutex_lock(&self.mutex);
        defer _ = std.c.pthread_mutex_unlock(&self.mutex);
        self.writeAll(json);
        self.writeAll("\n");
    }

    fn writeAll(self: *Emitter, bytes: []const u8) void {
        var written: usize = 0;
        while (written < bytes.len) {
            const n = std.c.write(self.fd, bytes.ptr + written, bytes.len - written);
            if (n <= 0) return;
            written += @intCast(n);
        }
    }
};

/// Reads a descriptor and hands back one line at a time without the newline. A line
/// longer than the buffer is reported rather than split, so a caller answers
/// `malformed` once instead of parsing two halves of a command as two commands.
pub const LineReader = struct {
    fd: std.c.fd_t = stdin_fd,
    buf: []u8,
    len: usize = 0,
    consumed: usize = 0,
    eof: bool = false,
    discarding: bool = false,

    pub const Line = union(enum) {
        line: []const u8,
        too_long,
        end,
    };

    pub fn next(self: *LineReader) Line {
        self.compact();
        while (true) {
            if (std.mem.indexOfScalar(u8, self.buf[0..self.len], '\n')) |nl| {
                self.consumed = nl + 1;
                if (self.discarding) {
                    self.discarding = false;
                    self.compact();
                    continue;
                }
                return .{ .line = self.buf[0..nl] };
            }
            if (self.eof) {
                if (self.discarding or self.len == 0) return .end;
                self.consumed = self.len;
                return .{ .line = self.buf[0..self.len] };
            }
            if (self.len == self.buf.len) {
                self.len = 0;
                if (self.discarding) continue;
                self.discarding = true;
                return .too_long;
            }
            const n = std.c.read(self.fd, self.buf.ptr + self.len, self.buf.len - self.len);
            if (n <= 0) self.eof = true else self.len += @intCast(n);
        }
    }

    fn compact(self: *LineReader) void {
        if (self.consumed == 0) return;
        const rest = self.buf[self.consumed..self.len];
        std.mem.copyForwards(u8, self.buf[0..rest.len], rest);
        self.len = rest.len;
        self.consumed = 0;
    }
};

fn pipeWith(bytes: []const u8) ![2]std.c.fd_t {
    var fds: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) return error.PipeFailed;
    var thread = try std.Thread.spawn(.{}, struct {
        fn run(w: std.c.fd_t, payload: []const u8) void {
            var off: usize = 0;
            while (off < payload.len) {
                const n = std.c.write(w, payload.ptr + off, payload.len - off);
                if (n <= 0) break;
                off += @intCast(n);
            }
            _ = std.c.close(w);
        }
    }.run, .{ fds[1], bytes });
    thread.detach();
    return fds;
}

test "line reader splits on newlines, keeps the remainder, then reports the end" {
    const fds = try pipeWith("{\"a\":1}\n{\"b\":2}\ntail");
    defer _ = std.c.close(fds[0]);
    var storage: [64]u8 = undefined;
    var reader: LineReader = .{ .fd = fds[0], .buf = &storage };

    try std.testing.expectEqualStrings("{\"a\":1}", reader.next().line);
    try std.testing.expectEqualStrings("{\"b\":2}", reader.next().line);
    try std.testing.expectEqualStrings("tail", reader.next().line);
    try std.testing.expect(reader.next() == .end);
}

test "a line past the buffer reports too_long once and resyncs on the next newline" {
    const fds = try pipeWith("aaaaaaaaaaaaaaaaaaaa\nok\n");
    defer _ = std.c.close(fds[0]);
    var storage: [8]u8 = undefined;
    var reader: LineReader = .{ .fd = fds[0], .buf = &storage };

    try std.testing.expect(reader.next() == .too_long);
    try std.testing.expectEqualStrings("ok", reader.next().line);
    try std.testing.expect(reader.next() == .end);
}

test "emitter writes one newline-terminated json object per call" {
    var fds: [2]std.c.fd_t = undefined;
    try std.testing.expect(std.c.pipe(&fds) == 0);
    defer _ = std.c.close(fds[0]);
    var emitter: Emitter = .{ .gpa = std.testing.allocator, .fd = fds[1] };
    emitter.line(.{ .type = "pong", .id = @as(?u32, 3) });
    emitter.line(.{ .type = "pong", .id = @as(?u32, null) });
    _ = std.c.close(fds[1]);

    var storage: [256]u8 = undefined;
    var reader: LineReader = .{ .fd = fds[0], .buf = &storage };
    try std.testing.expectEqualStrings("{\"type\":\"pong\",\"id\":3}", reader.next().line);
    try std.testing.expectEqualStrings("{\"type\":\"pong\",\"id\":null}", reader.next().line);
    try std.testing.expect(reader.next() == .end);
}
