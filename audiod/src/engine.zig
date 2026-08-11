const std = @import("std");
const pw = @import("pw.zig");
const c = pw.c;
const Emitter = @import("emit.zig").Emitter;

pub const protocol_version = 1;
pub const daemon_version = "0.1.0";
pub const max_channels = 64;
const max_sync_rounds = 16;

pub const Kind = struct { is_sink: bool, is_stream: bool };

/// Mirrors the four buckets `Audio.qml:43-46` builds out of `node.isSink` and
/// `node.isStream`. A class we do not recognise is not an audio node.
pub fn classify(media_class: []const u8) ?Kind {
    if (std.mem.startsWith(u8, media_class, "Audio/Sink")) return .{ .is_sink = true, .is_stream = false };
    if (std.mem.startsWith(u8, media_class, "Audio/Source")) return .{ .is_sink = false, .is_stream = false };
    if (std.mem.eql(u8, media_class, "Stream/Output/Audio")) return .{ .is_sink = true, .is_stream = true };
    if (std.mem.eql(u8, media_class, "Stream/Input/Audio")) return .{ .is_sink = false, .is_stream = true };
    return null;
}

pub const NodeJson = struct {
    id: u32,
    serial: ?u64,
    name: []const u8,
    description: ?[]const u8,
    nickname: ?[]const u8,
    application_name: ?[]const u8,
    media_class: []const u8,
    is_sink: bool,
    is_stream: bool,
    is_default: bool,
    ready: bool,
    volume: ?f32,
    channel_volumes: []const f32,
    mute: ?bool,
};

pub const Node = struct {
    engine: *Engine,
    id: u32,
    proxy: ?*c.struct_pw_node = null,
    listener: c.struct_spa_hook = std.mem.zeroes(c.struct_spa_hook),
    subscribed: bool = false,
    announced: bool = false,

    serial: ?u64 = null,
    name: []const u8 = "",
    description: ?[]const u8 = null,
    nickname: ?[]const u8 = null,
    application_name: ?[]const u8 = null,
    media_class: []const u8 = "",
    kind: Kind = .{ .is_sink = false, .is_stream = false },

    have_props: bool = false,
    mute: bool = false,
    channels: usize = 0,
    amplitudes: [max_channels]f32 = [_]f32{0} ** max_channels,

    /// A key missing from a later info event means unchanged, not cleared.
    fn setString(self: *Node, field: *?[]const u8, value: ?[]const u8) void {
        const v = value orelse return;
        const gpa = self.engine.gpa;
        if (field.*) |old| {
            if (std.mem.eql(u8, old, v)) return;
            gpa.free(old);
        }
        field.* = gpa.dupe(u8, v) catch null;
    }

    fn deinitStrings(self: *Node) void {
        const gpa = self.engine.gpa;
        if (self.name.len != 0) gpa.free(self.name);
        if (self.media_class.len != 0) gpa.free(self.media_class);
        if (self.description) |v| gpa.free(v);
        if (self.nickname) |v| gpa.free(v);
        if (self.application_name) |v| gpa.free(v);
    }

    /// `channel_volumes_out` receives the per-channel values in the protocol's scale.
    pub fn toJson(self: *const Node, channel_volumes_out: []f32) NodeJson {
        var sum: f32 = 0;
        var i: usize = 0;
        while (i < self.channels) : (i += 1) {
            channel_volumes_out[i] = pw.amplitudeToVolume(self.amplitudes[i]);
            sum += self.amplitudes[i];
        }
        const average: ?f32 = if (self.channels == 0)
            null
        else
            pw.amplitudeToVolume(sum / @as(f32, @floatFromInt(self.channels)));

        return .{
            .id = self.id,
            .serial = self.serial,
            .name = self.name,
            .description = self.description,
            .nickname = self.nickname,
            .application_name = self.application_name,
            .media_class = self.media_class,
            .is_sink = self.kind.is_sink,
            .is_stream = self.kind.is_stream,
            .is_default = self.engine.isDefault(self),
            .ready = self.have_props,
            .volume = if (self.have_props) average else null,
            .channel_volumes = channel_volumes_out[0..self.channels],
            .mute = if (self.have_props) self.mute else null,
        };
    }
};

pub const StartError = error{
    ContextFailed,
    ConnectFailed,
    RegistryFailed,
    LoopFailed,
    StartupTimeout,
};

pub const Engine = struct {
    gpa: std.mem.Allocator,
    emitter: *Emitter,

    loop: ?*c.struct_pw_thread_loop = null,
    context: ?*c.struct_pw_context = null,
    core: ?*c.struct_pw_core = null,
    registry: ?*c.struct_pw_registry = null,
    core_listener: c.struct_spa_hook = std.mem.zeroes(c.struct_spa_hook),
    core_proxy_listener: c.struct_spa_hook = std.mem.zeroes(c.struct_spa_hook),
    registry_listener: c.struct_spa_hook = std.mem.zeroes(c.struct_spa_hook),

    metadata: ?*c.struct_pw_metadata = null,
    metadata_id: u32 = 0,
    metadata_listener: c.struct_spa_hook = std.mem.zeroes(c.struct_spa_hook),

    nodes: std.AutoHashMap(u32, *Node),
    default_sink: ?[]const u8 = null,
    default_source: ?[]const u8 = null,

    ready: std.atomic.Value(bool) = .init(false),
    lost: std.atomic.Value(bool) = .init(false),
    stopping: std.atomic.Value(bool) = .init(false),
    snapshot_serial: u64 = 0,
    progress: u64 = 0,
    sync_progress: u64 = 0,
    sync_seq: c_int = 0,
    sync_rounds: u32 = 0,

    pub fn init(gpa: std.mem.Allocator, emitter: *Emitter) Engine {
        return .{ .gpa = gpa, .emitter = emitter, .nodes = std.AutoHashMap(u32, *Node).init(gpa) };
    }

    pub fn deinit(self: *Engine) void {
        // Tearing down the core fires the proxy `removed` callback; that is our own
        // doing, not pipewire going away.
        self.stopping.store(true, .release);
        if (self.loop) |loop| c.pw_thread_loop_stop(loop);
        var it = self.nodes.valueIterator();
        while (it.next()) |entry| {
            const node = entry.*;
            node.deinitStrings();
            self.gpa.destroy(node);
        }
        self.nodes.deinit();
        if (self.default_sink) |v| self.gpa.free(v);
        if (self.default_source) |v| self.gpa.free(v);
        if (self.core) |core| _ = c.pw_core_disconnect(core);
        if (self.context) |ctx| c.pw_context_destroy(ctx);
        if (self.loop) |loop| c.pw_thread_loop_destroy(loop);
    }

    pub fn lock(self: *Engine) void {
        c.pw_thread_loop_lock(self.loop);
    }

    pub fn unlock(self: *Engine) void {
        c.pw_thread_loop_unlock(self.loop);
    }

    /// Connects, starts the loop thread, and returns once the first registry
    /// roundtrip has settled. Bounded by `timeout_ms` so a live-but-unresponsive
    /// server produces an error instead of a hang.
    pub fn start(self: *Engine, timeout_ms: u64) StartError!void {
        self.loop = c.pw_thread_loop_new("audiod", null) orelse return error.LoopFailed;

        self.lock();
        if (c.pw_thread_loop_start(self.loop) < 0) {
            self.unlock();
            return error.LoopFailed;
        }

        self.context = c.pw_context_new(c.pw_thread_loop_get_loop(self.loop), null, 0) orelse {
            self.unlock();
            return error.ContextFailed;
        };
        self.core = c.pw_context_connect(self.context, null, 0) orelse {
            self.unlock();
            return error.ConnectFailed;
        };
        _ = c.pw_core_add_listener(self.core, &self.core_listener, &core_events, self);
        _ = c.pw_proxy_add_listener(@ptrCast(self.core), &self.core_proxy_listener, &core_proxy_events, self);

        self.registry = c.pw_core_get_registry(self.core, @intCast(c.PW_VERSION_REGISTRY), 0) orelse {
            self.unlock();
            return error.RegistryFailed;
        };
        _ = c.pw_registry_add_listener(self.registry, &self.registry_listener, &registry_events, self);
        self.sync();
        self.unlock();

        var waited: u64 = 0;
        while (waited < timeout_ms) {
            if (self.ready.load(.acquire)) return;
            if (self.lost.load(.acquire)) return error.ConnectFailed;
            const nap: std.c.timespec = .{ .sec = 0, .nsec = 5 * std.time.ns_per_ms };
            _ = std.c.nanosleep(&nap, null);
            waited += 5;
        }
        if (self.ready.load(.acquire)) return;
        return error.StartupTimeout;
    }

    fn sync(self: *Engine) void {
        self.sync_progress = self.progress;
        self.sync_seq = c.pw_core_sync(self.core, c.PW_ID_CORE, 0);
    }

    pub fn isDefault(self: *const Engine, node: *const Node) bool {
        if (node.kind.is_stream) return false;
        const target = if (node.kind.is_sink) self.default_sink else self.default_source;
        const name = target orelse return false;
        return std.mem.eql(u8, name, node.name);
    }

    pub fn findByName(self: *Engine, name: []const u8, is_sink: bool) ?*Node {
        var it = self.nodes.valueIterator();
        while (it.next()) |entry| {
            const node = entry.*;
            if (node.kind.is_stream or node.kind.is_sink != is_sink) continue;
            if (std.mem.eql(u8, node.name, name)) return node;
        }
        return null;
    }

    // ---- snapshot ----------------------------------------------------------

    /// Caller must hold the loop lock. Frees the returned buckets' backing memory
    /// through `Snapshot.deinit`.
    pub const Snapshot = struct {
        gpa: std.mem.Allocator,
        nodes: []NodeJson,
        volumes: []f32,
        output_devices: []NodeJson,
        input_devices: []NodeJson,
        output_streams: []NodeJson,
        input_streams: []NodeJson,

        pub fn deinit(self: *Snapshot) void {
            self.gpa.free(self.nodes);
            self.gpa.free(self.volumes);
        }
    };

    pub fn snapshot(self: *Engine) !Snapshot {
        const count = self.nodes.count();
        const nodes = try self.gpa.alloc(NodeJson, count);
        errdefer self.gpa.free(nodes);
        const volumes = try self.gpa.alloc(f32, count * max_channels);
        errdefer self.gpa.free(volumes);

        var buckets = [4]std.ArrayList(NodeJson){ .empty, .empty, .empty, .empty };
        defer for (&buckets) |*b| b.deinit(self.gpa);

        var i: usize = 0;
        var it = self.nodes.valueIterator();
        while (it.next()) |entry| {
            const node = entry.*;
            nodes[i] = node.toJson(volumes[i * max_channels ..][0..max_channels]);
            const bucket: usize = if (node.kind.is_stream)
                (if (node.kind.is_sink) 2 else 3)
            else
                (if (node.kind.is_sink) 0 else 1);
            try buckets[bucket].append(self.gpa, nodes[i]);
            i += 1;
        }

        for (&buckets) |*b| std.mem.sort(NodeJson, b.items, {}, lessById);

        return .{
            .gpa = self.gpa,
            .nodes = nodes,
            .volumes = volumes,
            .output_devices = try self.gpa.dupe(NodeJson, buckets[0].items),
            .input_devices = try self.gpa.dupe(NodeJson, buckets[1].items),
            .output_streams = try self.gpa.dupe(NodeJson, buckets[2].items),
            .input_streams = try self.gpa.dupe(NodeJson, buckets[3].items),
        };
    }

    fn lessById(_: void, a: NodeJson, b: NodeJson) bool {
        return a.id < b.id;
    }

    /// Caller must hold the loop lock.
    pub fn emitState(self: *Engine) void {
        self.snapshot_serial += 1;
        var snap = self.snapshot() catch {
            self.emitter.line(.{ .type = "error", .@"error" = "out_of_memory", .message = "could not build a state snapshot" });
            return;
        };
        defer {
            self.gpa.free(snap.output_devices);
            self.gpa.free(snap.input_devices);
            self.gpa.free(snap.output_streams);
            self.gpa.free(snap.input_streams);
            snap.deinit();
        }
        self.emitter.line(.{
            .type = "state",
            .serial = self.snapshot_serial,
            .ready = self.ready.load(.acquire),
            .default_sink = self.default_sink,
            .default_source = self.default_source,
            .output_devices = snap.output_devices,
            .input_devices = snap.input_devices,
            .output_streams = snap.output_streams,
            .input_streams = snap.input_streams,
        });
    }

    fn emitNode(self: *Engine, node: *Node, kind: []const u8) void {
        var volumes: [max_channels]f32 = undefined;
        self.emitter.line(.{ .type = kind, .node = node.toJson(&volumes) });
    }

    pub fn emitUnavailable(self: *Engine, reason: []const u8, message: []const u8) void {
        self.emitter.line(.{ .type = "unavailable", .reason = reason, .message = message });
    }

    // ---- writes -----------------------------------------------------------

    pub const WriteError = error{ NotReady, Rejected };

    /// Caller must hold the loop lock.
    pub fn setVolume(self: *Engine, node: *Node, volume: f32) WriteError!void {
        _ = self;
        if (!node.have_props or node.channels == 0) return error.NotReady;
        var amplitudes: [max_channels]f32 = undefined;
        const amplitude = pw.volumeToAmplitude(volume);
        for (amplitudes[0..node.channels]) |*a| a.* = amplitude;

        var buf: [1024]u8 = undefined;
        var builder: c.struct_spa_pod_builder = std.mem.zeroes(c.struct_spa_pod_builder);
        builder.data = &buf;
        builder.size = buf.len;
        var frame: c.struct_spa_pod_frame = std.mem.zeroes(c.struct_spa_pod_frame);
        _ = c.spa_pod_builder_push_object(&builder, &frame, c.SPA_TYPE_OBJECT_Props, c.SPA_PARAM_Props);
        _ = c.spa_pod_builder_prop(&builder, c.SPA_PROP_channelVolumes, 0);
        _ = c.spa_pod_builder_array(&builder, @sizeOf(f32), c.SPA_TYPE_Float, @intCast(node.channels), &amplitudes);
        const pod = c.spa_pod_builder_pop(&builder, &frame) orelse return error.Rejected;

        if (c.pw_node_set_param(node.proxy, c.SPA_PARAM_Props, 0, @ptrCast(@alignCast(pod))) < 0) return error.Rejected;
    }

    /// Caller must hold the loop lock.
    pub fn setMute(self: *Engine, node: *Node, mute: bool) WriteError!void {
        _ = self;
        if (node.proxy == null) return error.NotReady;
        var buf: [256]u8 = undefined;
        var builder: c.struct_spa_pod_builder = std.mem.zeroes(c.struct_spa_pod_builder);
        builder.data = &buf;
        builder.size = buf.len;
        var frame: c.struct_spa_pod_frame = std.mem.zeroes(c.struct_spa_pod_frame);
        _ = c.spa_pod_builder_push_object(&builder, &frame, c.SPA_TYPE_OBJECT_Props, c.SPA_PARAM_Props);
        _ = c.spa_pod_builder_prop(&builder, c.SPA_PROP_mute, 0);
        _ = c.spa_pod_builder_bool(&builder, mute);
        const pod = c.spa_pod_builder_pop(&builder, &frame) orelse return error.Rejected;

        if (c.pw_node_set_param(node.proxy, c.SPA_PARAM_Props, 0, @ptrCast(@alignCast(pod))) < 0) return error.Rejected;
    }

    /// Caller must hold the loop lock. Writes the key WirePlumber persists, which is
    /// the same one `Pipewire.preferredDefaultAudioSink` sets from `Audio.qml:73`.
    pub fn setDefault(self: *Engine, is_sink: bool, name: []const u8) WriteError!void {
        const metadata = self.metadata orelse return error.NotReady;
        var value_buf: [512]u8 = undefined;
        const value = std.fmt.bufPrintZ(&value_buf, "{f}", .{std.json.fmt(.{ .name = name }, .{})}) catch return error.Rejected;
        const key = if (is_sink) "default.configured.audio.sink" else "default.configured.audio.source";
        if (c.pw_metadata_set_property(metadata, 0, key, "Spa:String:JSON", value) < 0) return error.Rejected;
        return;
    }

    // ---- callbacks --------------------------------------------------------

    const core_events: c.struct_pw_core_events = .{
        .version = @intCast(c.PW_VERSION_CORE_EVENTS),
        .done = onCoreDone,
        .@"error" = onCoreError,
    };

    const core_proxy_events: c.struct_pw_proxy_events = .{
        .version = @intCast(c.PW_VERSION_PROXY_EVENTS),
        .removed = onCoreRemoved,
    };

    const registry_events: c.struct_pw_registry_events = .{
        .version = @intCast(c.PW_VERSION_REGISTRY_EVENTS),
        .global = onGlobal,
        .global_remove = onGlobalRemove,
    };

    const node_events: c.struct_pw_node_events = .{
        .version = @intCast(c.PW_VERSION_NODE_EVENTS),
        .info = onNodeInfo,
        .param = onNodeParam,
    };

    const metadata_events: c.struct_pw_metadata_events = .{
        .version = @intCast(c.PW_VERSION_METADATA_EVENTS),
        .property = onMetadataProperty,
    };

    fn onCoreDone(data: ?*anyopaque, id: u32, seq: c_int) callconv(.c) void {
        const self: *Engine = @ptrCast(@alignCast(data.?));
        if (id != c.PW_ID_CORE or seq != self.sync_seq) return;
        if (self.ready.load(.acquire)) return;

        self.sync_rounds += 1;
        if (self.progress != self.sync_progress and self.sync_rounds < max_sync_rounds) {
            self.sync();
            return;
        }
        self.ready.store(true, .release);
        self.emitState();
    }

    fn onCoreError(data: ?*anyopaque, id: u32, seq: c_int, res: c_int, message: [*c]const u8) callconv(.c) void {
        const self: *Engine = @ptrCast(@alignCast(data.?));
        _ = seq;
        if (id != c.PW_ID_CORE) return;
        self.emitter.line(.{
            .type = "error",
            .@"error" = "core",
            .message = if (message != null) std.mem.span(message) else "",
            .res = res,
        });
        if (res == -@as(c_int, @intCast(@intFromEnum(std.os.linux.E.PIPE)))) self.markLost("the pipewire connection closed");
    }

    fn onCoreRemoved(data: ?*anyopaque) callconv(.c) void {
        const self: *Engine = @ptrCast(@alignCast(data.?));
        self.markLost("the pipewire core proxy was removed");
    }

    fn markLost(self: *Engine, message: []const u8) void {
        if (self.stopping.load(.acquire)) return;
        if (self.lost.swap(true, .acq_rel)) return;
        self.emitUnavailable("disconnected", message);
        std.process.exit(1);
    }

    fn onGlobal(
        data: ?*anyopaque,
        id: u32,
        permissions: u32,
        global_type: [*c]const u8,
        version: u32,
        props: [*c]const c.struct_spa_dict,
    ) callconv(.c) void {
        const self: *Engine = @ptrCast(@alignCast(data.?));
        _ = permissions;
        _ = version;
        if (global_type == null) return;
        const t = std.mem.span(global_type);

        if (std.mem.eql(u8, t, c.PW_TYPE_INTERFACE_Node)) {
            const media_class = pw.dictLookup(props, "media.class") orelse return;
            const kind = classify(media_class) orelse return;
            self.addNode(id, media_class, kind);
            return;
        }
        if (std.mem.eql(u8, t, c.PW_TYPE_INTERFACE_Metadata)) {
            const name = pw.dictLookup(props, "metadata.name") orelse return;
            if (!std.mem.eql(u8, name, "default")) return;
            if (self.metadata != null) return;
            const proxy = c.pw_registry_bind(self.registry, id, c.PW_TYPE_INTERFACE_Metadata, @intCast(c.PW_VERSION_METADATA), 0) orelse return;
            self.metadata = @ptrCast(@alignCast(proxy));
            self.metadata_id = id;
            _ = c.pw_metadata_add_listener(self.metadata, &self.metadata_listener, &metadata_events, self);
            self.progress += 1;
        }
    }

    fn addNode(self: *Engine, id: u32, media_class: []const u8, kind: Kind) void {
        if (self.nodes.contains(id)) return;
        const node = self.gpa.create(Node) catch return;
        node.* = .{ .engine = self, .id = id, .kind = kind };
        node.media_class = self.gpa.dupe(u8, media_class) catch "";
        self.nodes.put(id, node) catch {
            node.deinitStrings();
            self.gpa.destroy(node);
            return;
        };

        const proxy = c.pw_registry_bind(self.registry, id, c.PW_TYPE_INTERFACE_Node, @intCast(c.PW_VERSION_NODE), 0);
        if (proxy == null) return;
        node.proxy = @ptrCast(@alignCast(proxy));
        _ = c.pw_node_add_listener(node.proxy, &node.listener, &node_events, node);
        self.progress += 1;
    }

    fn onGlobalRemove(data: ?*anyopaque, id: u32) callconv(.c) void {
        const self: *Engine = @ptrCast(@alignCast(data.?));
        if (self.metadata != null and id == self.metadata_id) {
            c.spa_hook_remove(&self.metadata_listener);
            c.pw_proxy_destroy(@ptrCast(self.metadata));
            self.metadata = null;
            return;
        }
        const entry = self.nodes.fetchRemove(id) orelse return;
        const node = entry.value;
        if (node.proxy != null) {
            c.spa_hook_remove(&node.listener);
            c.pw_proxy_destroy(@ptrCast(node.proxy));
        }
        const announced = node.announced;
        node.deinitStrings();
        self.gpa.destroy(node);
        self.progress += 1;
        if (announced and self.ready.load(.acquire)) {
            self.emitter.line(.{ .type = "node_removed", .id = id });
        }
    }

    fn onNodeInfo(data: ?*anyopaque, info: [*c]const c.struct_pw_node_info) callconv(.c) void {
        const node: *Node = @ptrCast(@alignCast(data.?));
        const self = node.engine;
        if (info == null) return;
        self.progress += 1;

        const props = info.*.props;
        if (props != null and (info.*.change_mask & c.PW_NODE_CHANGE_MASK_PROPS) != 0) {
            if (pw.dictLookup(props, "node.name")) |v| {
                if (node.name.len != 0) self.gpa.free(node.name);
                node.name = self.gpa.dupe(u8, v) catch "";
            }
            if (pw.dictLookup(props, "media.class")) |v| {
                if (!std.mem.eql(u8, v, node.media_class)) {
                    if (node.media_class.len != 0) self.gpa.free(node.media_class);
                    node.media_class = self.gpa.dupe(u8, v) catch "";
                    if (classify(node.media_class)) |k| node.kind = k;
                }
            }
            node.setString(&node.description, pw.dictLookup(props, "node.description"));
            node.setString(&node.nickname, pw.dictLookup(props, "node.nick"));
            node.setString(&node.application_name, pw.dictLookup(props, "application.name"));
            if (pw.dictLookup(props, "object.serial")) |v| {
                node.serial = std.fmt.parseInt(u64, v, 10) catch null;
            }
        }

        if (!node.subscribed) {
            node.subscribed = true;
            var ids = [_]u32{@intCast(c.SPA_PARAM_Props)};
            _ = c.pw_node_subscribe_params(node.proxy, &ids, ids.len);
        }
        self.announce(node);
    }

    fn onNodeParam(
        data: ?*anyopaque,
        seq: c_int,
        id: u32,
        index: u32,
        next: u32,
        param: [*c]const c.struct_spa_pod,
    ) callconv(.c) void {
        const node: *Node = @ptrCast(@alignCast(data.?));
        const self = node.engine;
        _ = seq;
        _ = index;
        _ = next;
        if (id != c.SPA_PARAM_Props or param == null) return;
        if (param.*.type != c.SPA_TYPE_Object) return;
        self.progress += 1;

        const object: *const c.struct_spa_pod_object = @ptrCast(@alignCast(param));
        var iter = pw.PropIter.init(object);
        var changed = false;
        while (iter.next()) |prop| {
            switch (prop.key) {
                c.SPA_PROP_mute => {
                    if (pw.podBool(&prop.value)) |m| {
                        if (m != node.mute) changed = true;
                        node.mute = m;
                    }
                },
                c.SPA_PROP_channelVolumes => {
                    var values: [max_channels]f32 = undefined;
                    if (pw.podFloatArray(&prop.value, &values)) |n| {
                        if (n != node.channels or !std.mem.eql(f32, node.amplitudes[0..n], values[0..n])) changed = true;
                        node.channels = n;
                        @memcpy(node.amplitudes[0..n], values[0..n]);
                    }
                },
                else => {},
            }
        }
        if (!node.have_props and node.channels != 0) {
            node.have_props = true;
            changed = true;
        }
        self.announce(node);
        if (changed and node.announced and self.ready.load(.acquire)) self.emitNode(node, "node_changed");
    }

    /// A node is announced once it has a name; before the initial state has gone out
    /// the snapshot carries it instead of an event.
    fn announce(self: *Engine, node: *Node) void {
        if (node.announced or node.name.len == 0) return;
        node.announced = true;
        if (self.ready.load(.acquire)) self.emitNode(node, "node_added");
    }

    fn onMetadataProperty(
        data: ?*anyopaque,
        subject: u32,
        key: [*c]const u8,
        value_type: [*c]const u8,
        value: [*c]const u8,
    ) callconv(.c) c_int {
        const self: *Engine = @ptrCast(@alignCast(data.?));
        _ = value_type;
        if (subject != 0 or key == null) return 0;
        const k = std.mem.span(key);
        const is_sink = std.mem.eql(u8, k, "default.audio.sink");
        const is_source = std.mem.eql(u8, k, "default.audio.source");
        if (!is_sink and !is_source) return 0;
        self.progress += 1;

        const name = if (value == null) null else parseDefaultName(self.gpa, std.mem.span(value));
        const slot = if (is_sink) &self.default_sink else &self.default_source;
        if (slot.*) |old| {
            if (name) |n| {
                if (std.mem.eql(u8, old, n)) {
                    self.gpa.free(n);
                    return 0;
                }
            }
            self.gpa.free(old);
        } else if (name == null) return 0;
        slot.* = name;

        if (self.ready.load(.acquire)) {
            self.emitter.line(.{
                .type = "defaults_changed",
                .default_sink = self.default_sink,
                .default_source = self.default_source,
            });
        }
        return 0;
    }
};

/// The metadata value is JSON: `{"name":"alsa_output..."}`.
pub fn parseDefaultName(gpa: std.mem.Allocator, value: []const u8) ?[]const u8 {
    const parsed = std.json.parseFromSlice(
        struct { name: ?[]const u8 = null },
        gpa,
        value,
        .{ .ignore_unknown_fields = true },
    ) catch return null;
    defer parsed.deinit();
    const name = parsed.value.name orelse return null;
    return gpa.dupe(u8, name) catch null;
}

test "media classes map onto the four buckets Audio.qml builds" {
    try std.testing.expectEqual(Kind{ .is_sink = true, .is_stream = false }, classify("Audio/Sink").?);
    try std.testing.expectEqual(Kind{ .is_sink = false, .is_stream = false }, classify("Audio/Source").?);
    try std.testing.expectEqual(Kind{ .is_sink = false, .is_stream = false }, classify("Audio/Source/Virtual").?);
    try std.testing.expectEqual(Kind{ .is_sink = true, .is_stream = true }, classify("Stream/Output/Audio").?);
    try std.testing.expectEqual(Kind{ .is_sink = false, .is_stream = true }, classify("Stream/Input/Audio").?);
    try std.testing.expect(classify("Video/Source") == null);
    try std.testing.expect(classify("Stream/Output/Video") == null);
}

test "the default metadata value yields the node name, and junk yields nothing" {
    const gpa = std.testing.allocator;
    const name = parseDefaultName(gpa, "{\"name\":\"alsa_output.pci-0000_00_1f.3\"}").?;
    defer gpa.free(name);
    try std.testing.expectEqualStrings("alsa_output.pci-0000_00_1f.3", name);

    try std.testing.expect(parseDefaultName(gpa, "{}") == null);
    try std.testing.expect(parseDefaultName(gpa, "not json") == null);
    try std.testing.expect(parseDefaultName(gpa, "{\"name\":null}") == null);
}
