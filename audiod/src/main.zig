const std = @import("std");
const pw = @import("pw.zig");
const c = pw.c;
const emit = @import("emit.zig");
const engine_mod = @import("engine.zig");
const Engine = engine_mod.Engine;

const default_startup_timeout_ms = 5000;
const max_command_bytes = 64 * 1024;

pub fn main() u8 {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const gpa = debug_allocator.allocator();

    var emitter: emit.Emitter = .{ .gpa = gpa };

    var argc: c_int = 0;
    c.pw_init(&argc, null);
    defer c.pw_deinit();

    emitter.line(.{
        .type = "hello",
        .protocol = engine_mod.protocol_version,
        .daemon = "audiod",
        .version = engine_mod.daemon_version,
        .pipewire = std.mem.span(c.pw_get_library_version()),
    });

    var engine = Engine.init(gpa, &emitter);
    defer engine.deinit();

    engine.start(startupTimeoutMs()) catch |err| {
        engine.emitUnavailable(reasonFor(err), messageFor(err));
        return 1;
    };

    return serve(&engine, gpa);
}

fn startupTimeoutMs() u64 {
    const raw = std.c.getenv("AUDIOD_STARTUP_TIMEOUT_MS") orelse return default_startup_timeout_ms;
    return std.fmt.parseInt(u64, std.mem.span(raw), 10) catch default_startup_timeout_ms;
}

fn reasonFor(err: engine_mod.StartError) []const u8 {
    return switch (err) {
        error.ConnectFailed => "connect_failed",
        error.StartupTimeout => "startup_timeout",
        error.LoopFailed => "loop_failed",
        error.ContextFailed => "context_failed",
        error.RegistryFailed => "registry_failed",
    };
}

fn messageFor(err: engine_mod.StartError) []const u8 {
    return switch (err) {
        error.ConnectFailed => "could not connect to pipewire",
        error.StartupTimeout => "pipewire accepted the connection but never answered the first sync",
        error.LoopFailed => "could not start the pipewire loop thread",
        error.ContextFailed => "could not create a pipewire context",
        error.RegistryFailed => "could not obtain the pipewire registry",
    };
}

fn serve(engine: *Engine, gpa: std.mem.Allocator) u8 {
    const buf = gpa.alloc(u8, max_command_bytes) catch return 1;
    defer gpa.free(buf);
    var reader: emit.LineReader = .{ .buf = buf };

    while (true) {
        switch (reader.next()) {
            .end => return 0,
            .too_long => engine.emitter.line(.{
                .type = "reply",
                .id = @as(?i64, null),
                .ok = false,
                .@"error" = "malformed",
                .message = "the command line exceeded the input buffer",
            }),
            .line => |line| {
                if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
                if (dispatch(engine, gpa, line)) return 0;
            },
        }
    }
}

/// Returns true when the daemon has been asked to quit.
fn dispatch(engine: *Engine, gpa: std.mem.Allocator, line: []const u8) bool {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const parsed = std.json.parseFromSlice(std.json.Value, arena, line, .{}) catch {
        fail(engine, null, "malformed", "the line is not valid JSON");
        return false;
    };
    const object = switch (parsed.value) {
        .object => |o| o,
        else => {
            fail(engine, null, "malformed", "the line is not a JSON object");
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
            fail(engine, id, "malformed", "the object has no string \"cmd\" field");
            return false;
        },
    };

    if (std.mem.eql(u8, cmd, "ping")) {
        ok(engine, id);
        return false;
    }
    if (std.mem.eql(u8, cmd, "quit")) {
        ok(engine, id);
        return true;
    }
    if (std.mem.eql(u8, cmd, "get_state")) {
        engine.lock();
        engine.emitState();
        engine.unlock();
        ok(engine, id);
        return false;
    }
    if (std.mem.eql(u8, cmd, "set_volume")) {
        runNodeWrite(engine, id, object, .volume);
        return false;
    }
    if (std.mem.eql(u8, cmd, "set_mute")) {
        runNodeWrite(engine, id, object, .mute);
        return false;
    }
    if (std.mem.eql(u8, cmd, "set_default_sink")) {
        runSetDefault(engine, id, object, true);
        return false;
    }
    if (std.mem.eql(u8, cmd, "set_default_source")) {
        runSetDefault(engine, id, object, false);
        return false;
    }

    fail(engine, id, "unknown_command", cmd);
    return false;
}

const WriteKind = enum { volume, mute };

fn runNodeWrite(engine: *Engine, id: ?i64, object: std.json.ObjectMap, kind: WriteKind) void {
    const node_id: u32 = switch (object.get("node") orelse std.json.Value{ .null = {} }) {
        .integer => |v| if (v >= 0 and v <= std.math.maxInt(u32)) @intCast(v) else {
            fail(engine, id, "bad_request", "\"node\" is not a valid node id");
            return;
        },
        else => {
            fail(engine, id, "bad_request", "\"node\" must be an integer node id");
            return;
        },
    };

    var volume: f32 = 0;
    var mute = false;
    switch (kind) {
        .volume => {
            volume = switch (object.get("volume") orelse std.json.Value{ .null = {} }) {
                .float => |v| @floatCast(v),
                .integer => |v| @floatFromInt(v),
                else => {
                    fail(engine, id, "bad_request", "\"volume\" must be a number");
                    return;
                },
            };
            if (!(volume >= 0) or volume > 2.0) {
                fail(engine, id, "bad_request", "\"volume\" must be between 0 and 2");
                return;
            }
        },
        .mute => {
            mute = switch (object.get("mute") orelse std.json.Value{ .null = {} }) {
                .bool => |v| v,
                else => {
                    fail(engine, id, "bad_request", "\"mute\" must be a boolean");
                    return;
                },
            };
        },
    }

    engine.lock();
    const node = engine.nodes.get(node_id);
    const result = if (node) |n| switch (kind) {
        .volume => engine.setVolume(n, volume),
        .mute => engine.setMute(n, mute),
    } else {};
    engine.unlock();

    if (node == null) {
        fail(engine, id, "unknown_node", "no audio node with that id");
        return;
    }
    reportWrite(engine, id, result);
}

fn runSetDefault(engine: *Engine, id: ?i64, object: std.json.ObjectMap, is_sink: bool) void {
    const name = switch (object.get("name") orelse std.json.Value{ .null = {} }) {
        .string => |s| s,
        else => {
            fail(engine, id, "bad_request", "\"name\" must be a node name string");
            return;
        },
    };

    engine.lock();
    const known = engine.findByName(name, is_sink) != null;
    const result = if (known) engine.setDefault(is_sink, name) else {};
    engine.unlock();

    if (!known) {
        fail(engine, id, "unknown_node", "no audio device with that node name");
        return;
    }
    reportWrite(engine, id, result);
}

fn reportWrite(engine: *Engine, id: ?i64, result: Engine.WriteError!void) void {
    if (result) |_| {
        ok(engine, id);
    } else |err| switch (err) {
        error.NotReady => fail(engine, id, "not_ready", "the node has not published its Props yet"),
        error.Rejected => fail(engine, id, "rejected", "pipewire rejected the parameter"),
    }
}

fn ok(engine: *Engine, id: ?i64) void {
    engine.emitter.line(.{ .type = "reply", .id = id, .ok = true });
}

fn fail(engine: *Engine, id: ?i64, code: []const u8, message: []const u8) void {
    engine.emitter.line(.{ .type = "reply", .id = id, .ok = false, .@"error" = code, .message = message });
}

test {
    std.testing.refAllDecls(@This());
    _ = pw;
    _ = emit;
    _ = engine_mod;
}
