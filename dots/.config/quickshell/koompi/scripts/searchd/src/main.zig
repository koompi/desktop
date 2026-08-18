const std = @import("std");
const posix = std.posix;
const emit = @import("emit.zig");
const index_mod = @import("index.zig");
const store_mod = @import("store.zig");
const Index = index_mod.Index;
const Store = store_mod.Store;

const protocol_version = 1;
const daemon_version = "0.1.0";
// shelld's 256 KiB line cap fits its small control messages, but "update"
// pushes a whole clipboard/apps snapshot in one line - 7500 clipboard
// entries measured close to 1 MiB of JSON. 8 MiB covers real-machine scale
// with headroom; still a hard cap, not unbounded.
const max_command_bytes = 8 * 1024 * 1024;
const default_limit: usize = 30; // matches FileSearch.qml's fd --max-results 30
const max_limit: usize = 200;

pub fn main() u8 {
    // Not DebugAllocator: the index is tens of thousands of small individual
    // path allocations, and DebugAllocator's per-allocation tracking cost
    // alone measured ~600 bytes/entry here - 8x the whole steady-PSS budget.
    // c_allocator (glibc malloc, already linked for emit.zig's std.c calls)
    // has none of that overhead. Tests still use std.testing.allocator, which
    // keeps the leak checking this trades away.
    const gpa = std.heap.c_allocator;

    var emitter: emit.Emitter = .{ .gpa = gpa };
    emitter.line(.{
        .type = "hello",
        .protocol = protocol_version,
        .daemon = "searchd",
        .version = daemon_version,
        .services = &[_][]const u8{ "files", "clipboard", "apps" },
    });

    const home = std.c.getenv("HOME") orelse {
        emitter.line(.{ .type = "unavailable", .service = "files", .reason = "no_home", .message = "HOME is not set" });
        return 1;
    };

    var idx = Index.init(gpa, std.mem.span(home)) catch |err| {
        emitter.line(.{
            .type = "unavailable",
            .service = "files",
            .reason = "index_init_failed",
            .message = @errorName(err),
        });
        return 1;
    };
    defer idx.deinit();

    emitter.line(.{
        .type = "state",
        .service = "files",
        .ready = true,
        .entryCount = idx.entries.items.len,
        .buildMs = idx.build_ms,
    });

    // clipboard and apps have no daemon-visible change signal to watch (a
    // Wayland clipboard event and DesktopEntries are both QML-side only) -
    // QML pushes a snapshot via "update" instead of the daemon walking or
    // watching anything for them. Both start empty and "ready" immediately;
    // a "search" against an empty store is a real, if unhelpful, empty
    // result rather than "unavailable" - the same posture `files` takes
    // toward a `$HOME` with nothing indexable in it yet.
    var clipboard = Store.init(gpa);
    defer clipboard.deinit();
    emitter.line(.{ .type = "state", .service = "clipboard", .ready = true, .entryCount = @as(usize, 0) });

    var apps = Store.init(gpa);
    defer apps.deinit();
    emitter.line(.{ .type = "state", .service = "apps", .ready = true, .entryCount = @as(usize, 0) });

    return serve(&idx, &clipboard, &apps, &emitter, gpa);
}

fn serve(idx: *Index, clipboard: *Store, apps: *Store, emitter: *emit.Emitter, gpa: std.mem.Allocator) u8 {
    const buf = gpa.alloc(u8, max_command_bytes) catch return 1;
    defer gpa.free(buf);
    var reader: emit.LineReader = .{ .buf = buf };
    const stdin_fd: i32 = std.c.STDIN_FILENO;

    while (true) {
        var pfds = [2]posix.pollfd{
            .{ .fd = stdin_fd, .events = posix.POLL.IN, .revents = 0 },
            .{ .fd = idx.inotify_fd, .events = posix.POLL.IN, .revents = 0 },
        };
        _ = posix.poll(&pfds, -1) catch continue;

        if (pfds[1].revents & posix.POLL.IN != 0) {
            _ = idx.drainEvents() catch {};
        }

        if (pfds[0].revents & (posix.POLL.IN | posix.POLL.HUP) == 0) continue;

        // One read() per poll-reported-readable is enough in practice: a
        // request is at most a few thousand bytes (an "update" pushing a
        // clipboard/apps snapshot is the largest) and QML's Process.write()
        // sends it as a single write(), so LineReader's internal read loop
        // resolves without blocking. A pathologically fragmented write would
        // stall inotify draining until the rest of the line arrives -
        // accepted, matching audiod's equally blocking LineReader with no
        // multiplexing at all.
        switch (reader.next()) {
            .end => return 0,
            .too_long => emitter.line(.{
                .type = "reply",
                .id = @as(?i64, null),
                .ok = false,
                .@"error" = "malformed",
                .message = "the command line exceeded the input buffer",
            }),
            .line => |line| {
                if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
                if (dispatch(idx, clipboard, apps, emitter, gpa, line)) return 0;
            },
        }
    }
}

/// Returns true when the daemon has been asked to quit.
fn dispatch(idx: *Index, clipboard: *Store, apps: *Store, emitter: *emit.Emitter, gpa: std.mem.Allocator, line: []const u8) bool {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const parsed = std.json.parseFromSlice(std.json.Value, arena, line, .{}) catch {
        fail(emitter, null, "malformed", "the line is not valid JSON");
        return false;
    };
    const object = switch (parsed.value) {
        .object => |o| o,
        else => {
            fail(emitter, null, "malformed", "the line is not a JSON object");
            return false;
        },
    };

    const id: ?i64 = switch (object.get("id") orelse std.json.Value{ .null = {} }) {
        .integer => |v| v,
        else => null,
    };

    const cmd = switch (object.get("cmd") orelse std.json.Value{ .null = {} }) {
        .string => |s| s,
        else => {
            fail(emitter, id, "malformed", "the object has no string \"cmd\" field");
            return false;
        },
    };

    if (std.mem.eql(u8, cmd, "ping")) {
        ok(emitter, id);
        return false;
    }
    if (std.mem.eql(u8, cmd, "quit")) {
        ok(emitter, id);
        return true;
    }
    if (std.mem.eql(u8, cmd, "search")) {
        runSearch(idx, clipboard, apps, emitter, arena, id, object);
        return false;
    }
    if (std.mem.eql(u8, cmd, "update")) {
        runUpdate(clipboard, apps, emitter, arena, id, object);
        return false;
    }

    fail(emitter, id, "unknown_command", cmd);
    return false;
}

fn parseService(emitter: *emit.Emitter, id: ?i64, object: std.json.ObjectMap) ?[]const u8 {
    const service = switch (object.get("service") orelse std.json.Value{ .null = {} }) {
        .string => |s| s,
        else => {
            fail(emitter, id, "bad_request", "\"service\" must be a string");
            return null;
        },
    };
    if (std.mem.eql(u8, service, "files") or std.mem.eql(u8, service, "clipboard") or std.mem.eql(u8, service, "apps")) {
        return service;
    }
    fail(emitter, id, "unknown_service", service);
    return null;
}

fn runSearch(idx: *Index, clipboard: *Store, apps: *Store, emitter: *emit.Emitter, arena: std.mem.Allocator, id: ?i64, object: std.json.ObjectMap) void {
    if (id == null) {
        fail(emitter, null, "bad_request", "\"search\" requires an integer \"id\" - a reply can't be matched to its request without one");
        return;
    }
    const service = parseService(emitter, id, object) orelse return;

    const query = switch (object.get("query") orelse std.json.Value{ .null = {} }) {
        .string => |s| s,
        else => {
            fail(emitter, id, "bad_request", "\"query\" must be a string");
            return;
        },
    };

    var limit: usize = default_limit;
    if (object.get("limit")) |v| switch (v) {
        .integer => |n| limit = std.math.clamp(if (n < 0) 0 else @as(usize, @intCast(n)), 1, max_limit),
        .null => {},
        else => {
            fail(emitter, id, "bad_request", "\"limit\" must be an integer");
            return;
        },
    };

    if (std.mem.eql(u8, service, "files")) {
        // Matches FileSearch.qml:71's own `search.length < 2` gate - clipboard
        // and apps have no such floor (Cliphist.fuzzyQuery/AppSearch.fuzzyQuery
        // both run on a short or empty query too).
        if (query.len < 2) {
            emitter.line(.{ .type = "reply", .id = id, .ok = true, .service = "files", .results = &[_]Index.Match{}, .total = @as(usize, 0) });
            return;
        }
        const out = arena.alloc(Index.Match, limit) catch {
            fail(emitter, id, "rejected", "out of memory");
            return;
        };
        const result = idx.query(arena, query, limit, out) catch {
            fail(emitter, id, "rejected", "out of memory");
            return;
        };
        emitter.line(.{ .type = "reply", .id = id, .ok = true, .service = "files", .results = out[0..result.returned], .total = result.total });
        return;
    }

    const store = if (std.mem.eql(u8, service, "clipboard")) clipboard else apps;
    const out = arena.alloc(Store.Match, limit) catch {
        fail(emitter, id, "rejected", "out of memory");
        return;
    };
    const n = store.query(query, limit, out);
    emitter.line(.{ .type = "reply", .id = id, .ok = true, .service = service, .results = out[0..n], .total = store.countMatches(query) });
}

/// `{"cmd":"update","id":N,"service":"clipboard"|"apps","entries":[{"id":"...","name":"..."}]}`
/// Replaces that service's whole dataset. Never valid for `files`, which owns
/// its own index - `bad_request`, not silently ignored.
fn runUpdate(clipboard: *Store, apps: *Store, emitter: *emit.Emitter, arena: std.mem.Allocator, id: ?i64, object: std.json.ObjectMap) void {
    const service = parseService(emitter, id, object) orelse return;
    if (std.mem.eql(u8, service, "files")) {
        fail(emitter, id, "bad_request", "\"files\" builds its own index and does not take \"update\"");
        return;
    }

    const entries_value = switch (object.get("entries") orelse std.json.Value{ .null = {} }) {
        .array => |a| a,
        else => {
            fail(emitter, id, "bad_request", "\"entries\" must be an array of {id, name}");
            return;
        },
    };

    var pairs = arena.alloc([2][]const u8, entries_value.items.len) catch {
        fail(emitter, id, "rejected", "out of memory");
        return;
    };
    for (entries_value.items, 0..) |item, i| {
        const obj = switch (item) {
            .object => |o| o,
            else => {
                fail(emitter, id, "bad_request", "every \"entries\" item must be an object with \"id\" and \"name\" strings");
                return;
            },
        };
        const eid = switch (obj.get("id") orelse std.json.Value{ .null = {} }) {
            .string => |s| s,
            else => {
                fail(emitter, id, "bad_request", "every entry needs a string \"id\"");
                return;
            },
        };
        const ename = switch (obj.get("name") orelse std.json.Value{ .null = {} }) {
            .string => |s| s,
            else => {
                fail(emitter, id, "bad_request", "every entry needs a string \"name\"");
                return;
            },
        };
        pairs[i] = .{ eid, ename };
    }

    const store = if (std.mem.eql(u8, service, "clipboard")) clipboard else apps;
    store.replace(pairs) catch {
        fail(emitter, id, "rejected", "out of memory");
        return;
    };
    emitter.line(.{ .type = "reply", .id = id, .ok = true, .service = service, .count = store.entries.items.len });
}

fn ok(emitter: *emit.Emitter, id: ?i64) void {
    emitter.line(.{ .type = "reply", .id = id, .ok = true });
}

fn fail(emitter: *emit.Emitter, id: ?i64, code: []const u8, message: []const u8) void {
    emitter.line(.{ .type = "reply", .id = id, .ok = false, .@"error" = code, .message = message });
}

test {
    std.testing.refAllDecls(@This());
    _ = emit;
    _ = index_mod;
    _ = store_mod;
}
