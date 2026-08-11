const std = @import("std");

pub const c = @cImport({
    @cInclude("pipewire/pipewire.h");
    @cInclude("pipewire/extensions/metadata.h");
    @cInclude("spa/param/props.h");
    @cInclude("spa/pod/builder.h");
    @cInclude("spa/utils/result.h");
});

pub fn dictLookup(dict: [*c]const c.struct_spa_dict, key: []const u8) ?[]const u8 {
    if (dict == null) return null;
    const items = dict.*.items;
    if (items == null) return null;
    var i: u32 = 0;
    while (i < dict.*.n_items) : (i += 1) {
        const item = items[i];
        if (item.key == null or item.value == null) continue;
        if (std.mem.eql(u8, std.mem.span(item.key), key)) return std.mem.span(item.value);
    }
    return null;
}

// spa_pod_prop_first/next and spa_pod_object_find_prop are SPA_PTROFF macros that
// translate-c drops. The walk below is that arithmetic over the @cImport structs.
const pod_align = 8;

fn roundUp(v: usize) usize {
    return (v + (pod_align - 1)) & ~@as(usize, pod_align - 1);
}

pub const PropIter = struct {
    body_start: [*]const u8,
    body_size: usize,
    cur: usize,

    pub fn init(object: *const c.struct_spa_pod_object) PropIter {
        const body: [*]const u8 = @ptrCast(&object.body);
        return .{
            .body_start = body,
            .body_size = object.pod.size,
            .cur = @sizeOf(c.struct_spa_pod_object_body),
        };
    }

    pub fn next(self: *PropIter) ?*const c.struct_spa_pod_prop {
        if (self.cur + @sizeOf(c.struct_spa_pod_prop) > self.body_size) return null;
        const prop: *const c.struct_spa_pod_prop = @ptrCast(@alignCast(self.body_start + self.cur));
        const size = @sizeOf(c.struct_spa_pod_prop) + @as(usize, prop.value.size);
        if (self.cur + size > self.body_size) return null;
        self.cur += roundUp(size);
        return prop;
    }
};

fn podBody(pod: *const c.struct_spa_pod) [*]const u8 {
    const base: [*]const u8 = @ptrCast(pod);
    return base + @sizeOf(c.struct_spa_pod);
}

pub fn podFloat(pod: *const c.struct_spa_pod) ?f32 {
    if (pod.type != c.SPA_TYPE_Float or pod.size != @sizeOf(f32)) return null;
    return std.mem.bytesToValue(f32, podBody(pod)[0..@sizeOf(f32)]);
}

pub fn podBool(pod: *const c.struct_spa_pod) ?bool {
    if (pod.type != c.SPA_TYPE_Bool or pod.size != @sizeOf(i32)) return null;
    return std.mem.bytesToValue(i32, podBody(pod)[0..@sizeOf(i32)]) != 0;
}

/// Floats out of a `SPA_TYPE_Array` of floats, written into `out`. Returns the count.
pub fn podFloatArray(pod: *const c.struct_spa_pod, out: []f32) ?usize {
    if (pod.type != c.SPA_TYPE_Array) return null;
    if (pod.size < @sizeOf(c.struct_spa_pod_array_body)) return null;
    const body: *const c.struct_spa_pod_array_body = @ptrCast(@alignCast(podBody(pod)));
    if (body.child.type != c.SPA_TYPE_Float or body.child.size != @sizeOf(f32)) return null;
    const values = podBody(pod) + @sizeOf(c.struct_spa_pod_array_body);
    const n = @min((pod.size - @sizeOf(c.struct_spa_pod_array_body)) / @sizeOf(f32), out.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[i] = std.mem.bytesToValue(f32, values[i * @sizeOf(f32) ..][0..@sizeOf(f32)]);
    }
    return n;
}

/// PipeWire stores a linear amplitude; wpctl, pavucontrol and `PwNodeAudio.volume`
/// all show its cube root. PROTOCOL.md calls the cube root `volume`.
pub fn amplitudeToVolume(amplitude: f32) f32 {
    if (amplitude <= 0) return 0;
    return std.math.cbrt(amplitude);
}

pub fn volumeToAmplitude(volume: f32) f32 {
    if (volume <= 0) return 0;
    return volume * volume * volume;
}

test "round trip volume scaling matches the value wpctl prints" {
    // 0.316756 is the live speaker amplitude captured while writing this; wpctl
    // rounds the same number to 0.68.
    try std.testing.expectApproxEqAbs(@as(f32, 0.68), amplitudeToVolume(0.316756), 0.005);
    try std.testing.expectApproxEqAbs(@as(f32, 0.316756), volumeToAmplitude(0.6817), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.42), amplitudeToVolume(volumeToAmplitude(0.42)), 0.0001);
    try std.testing.expectEqual(@as(f32, 0), amplitudeToVolume(0));
    try std.testing.expectEqual(@as(f32, 0), volumeToAmplitude(-1));
}

test "pod prop iteration walks a builder-produced Props object" {
    var buf: [512]u8 = undefined;
    var builder: c.struct_spa_pod_builder = std.mem.zeroes(c.struct_spa_pod_builder);
    builder.data = &buf;
    builder.size = buf.len;
    var frame: c.struct_spa_pod_frame = std.mem.zeroes(c.struct_spa_pod_frame);

    _ = c.spa_pod_builder_push_object(&builder, &frame, c.SPA_TYPE_OBJECT_Props, c.SPA_PARAM_Props);
    _ = c.spa_pod_builder_prop(&builder, c.SPA_PROP_mute, 0);
    _ = c.spa_pod_builder_bool(&builder, true);
    _ = c.spa_pod_builder_prop(&builder, c.SPA_PROP_channelVolumes, 0);
    const amps = [_]f32{ 0.25, 0.5 };
    _ = c.spa_pod_builder_array(&builder, @sizeOf(f32), c.SPA_TYPE_Float, amps.len, &amps);
    const pod: *const c.struct_spa_pod = @ptrCast(@alignCast(c.spa_pod_builder_pop(&builder, &frame).?));

    try std.testing.expect(pod.type == c.SPA_TYPE_Object);
    var iter = PropIter.init(@ptrCast(pod));
    var seen_mute: ?bool = null;
    var seen: [8]f32 = undefined;
    var seen_n: ?usize = null;
    while (iter.next()) |prop| {
        switch (prop.key) {
            c.SPA_PROP_mute => seen_mute = podBool(&prop.value),
            c.SPA_PROP_channelVolumes => seen_n = podFloatArray(&prop.value, &seen),
            else => {},
        }
    }
    try std.testing.expectEqual(@as(?bool, true), seen_mute);
    try std.testing.expectEqual(@as(?usize, 2), seen_n);
    try std.testing.expectEqual(@as(f32, 0.25), seen[0]);
    try std.testing.expectEqual(@as(f32, 0.5), seen[1]);
}
