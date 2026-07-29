// Hand-written bindings for the slice of GLib/GDBus the daemon uses.
//
// @cImport cannot digest glib's headers: translate-c chokes on the _Pragma
// inside G_DECLARE_*_TYPE and on the autoptr cleanup macros. The surface we
// need is about thirty stable functions, so we declare them instead. Typed
// GVariant constructors are used everywhere in preference to the varargs
// g_variant_new(), which would put format-string parsing between us and the
// ABI.

const std = @import("std");

pub const Connection = opaque {};
pub const Variant = opaque {};
pub const VariantType = opaque {};
pub const Cancellable = opaque {};
pub const MainLoop = opaque {};
pub const MainContext = opaque {};
pub const NodeInfo = opaque {};
pub const InterfaceInfo = opaque {};
pub const MethodInvocation = opaque {};

pub const Error = extern struct {
    domain: u32,
    code: c_int,
    message: [*:0]u8,
};

pub const BUS_TYPE_SESSION: c_int = 2;

pub const CALL_FLAGS_NONE: c_int = 0;
pub const CALL_FLAGS_NO_AUTO_START: c_int = 1 << 0;

pub const NAME_OWNER_FLAGS_NONE: c_int = 0;
pub const NAME_OWNER_FLAGS_REPLACE: c_int = 1 << 1;

pub const IO_IN: c_int = 1;
pub const IO_HUP: c_int = 16;
pub const IO_ERR: c_int = 8;

pub const PRIORITY_DEFAULT: c_int = 0;

pub const SIGNAL_FLAGS_NONE: c_int = 0;

pub const MethodCallFunc = *const fn (
    conn: *Connection,
    sender: [*:0]const u8,
    object_path: [*:0]const u8,
    interface_name: [*:0]const u8,
    method_name: [*:0]const u8,
    parameters: *Variant,
    invocation: *MethodInvocation,
    user_data: ?*anyopaque,
) callconv(.c) void;

pub const InterfaceVTable = extern struct {
    method_call: ?MethodCallFunc,
    get_property: ?*const anyopaque = null,
    set_property: ?*const anyopaque = null,
    padding: [8]?*anyopaque = .{null} ** 8,
};

pub const SignalCallback = *const fn (
    conn: *Connection,
    sender_name: ?[*:0]const u8,
    object_path: [*:0]const u8,
    interface_name: [*:0]const u8,
    signal_name: [*:0]const u8,
    parameters: *Variant,
    user_data: ?*anyopaque,
) callconv(.c) void;

pub const UnixFdSourceFunc = *const fn (
    fd: c_int,
    condition: c_int,
    user_data: ?*anyopaque,
) callconv(.c) c_int;

pub const NameCallback = *const fn (
    conn: *Connection,
    name: [*:0]const u8,
    user_data: ?*anyopaque,
) callconv(.c) void;

pub extern fn g_free(mem: ?*anyopaque) void;
pub extern fn g_error_free(err: *Error) void;

pub extern fn g_bus_get_sync(bus_type: c_int, cancellable: ?*Cancellable, err: *?*Error) ?*Connection;
pub extern fn g_dbus_connection_get_unique_name(conn: *Connection) ?[*:0]const u8;
pub extern fn g_dbus_connection_call_sync(
    conn: *Connection,
    bus_name: ?[*:0]const u8,
    object_path: [*:0]const u8,
    interface_name: [*:0]const u8,
    method_name: [*:0]const u8,
    parameters: ?*Variant,
    reply_type: ?*const VariantType,
    flags: c_int,
    timeout_msec: c_int,
    cancellable: ?*Cancellable,
    err: *?*Error,
) ?*Variant;
pub extern fn g_dbus_connection_register_object(
    conn: *Connection,
    object_path: [*:0]const u8,
    interface_info: *InterfaceInfo,
    vtable: *const InterfaceVTable,
    user_data: ?*anyopaque,
    user_data_free_func: ?*const anyopaque,
    err: *?*Error,
) c_uint;
pub extern fn g_dbus_connection_signal_subscribe(
    conn: *Connection,
    sender: ?[*:0]const u8,
    interface_name: ?[*:0]const u8,
    member: ?[*:0]const u8,
    object_path: ?[*:0]const u8,
    arg0: ?[*:0]const u8,
    flags: c_int,
    callback: SignalCallback,
    user_data: ?*anyopaque,
    user_data_free_func: ?*const anyopaque,
) c_uint;
pub extern fn g_dbus_node_info_new_for_xml(xml: [*:0]const u8, err: *?*Error) ?*NodeInfo;
pub extern fn g_dbus_node_info_lookup_interface(info: *NodeInfo, name: [*:0]const u8) ?*InterfaceInfo;
pub extern fn g_dbus_method_invocation_return_value(inv: *MethodInvocation, params: ?*Variant) void;
pub extern fn g_dbus_method_invocation_return_dbus_error(
    inv: *MethodInvocation,
    error_name: [*:0]const u8,
    error_message: [*:0]const u8,
) void;
pub extern fn g_dbus_method_invocation_get_sender(inv: *MethodInvocation) [*:0]const u8;
pub extern fn g_bus_own_name_on_connection(
    conn: *Connection,
    name: [*:0]const u8,
    flags: c_int,
    name_acquired: ?NameCallback,
    name_lost: ?NameCallback,
    user_data: ?*anyopaque,
    free_func: ?*const anyopaque,
) c_uint;

pub extern fn g_variant_new_string(str: [*:0]const u8) *Variant;
pub extern fn g_variant_new_object_path(str: [*:0]const u8) *Variant;
pub extern fn g_variant_new_uint32(v: u32) *Variant;
pub extern fn g_variant_new_int32(v: i32) *Variant;
pub extern fn g_variant_new_boolean(v: c_int) *Variant;
pub extern fn g_variant_new_variant(v: *Variant) *Variant;
pub extern fn g_variant_new_tuple(children: ?[*]const *Variant, n_children: usize) *Variant;
pub extern fn g_variant_new_array(
    child_type: ?*const VariantType,
    children: ?[*]const *Variant,
    n_children: usize,
) *Variant;
pub extern fn g_variant_type_new(type_string: [*:0]const u8) *VariantType;
pub extern fn g_variant_type_free(t: *VariantType) void;
pub extern fn g_variant_get_string(v: *Variant, length: ?*usize) [*:0]const u8;
pub extern fn g_variant_get_uint32(v: *Variant) u32;
pub extern fn g_variant_get_int32(v: *Variant) i32;
pub extern fn g_variant_get_boolean(v: *Variant) c_int;
pub extern fn g_variant_n_children(v: *Variant) usize;
pub extern fn g_variant_get_child_value(v: *Variant, index: usize) *Variant;
pub extern fn g_variant_lookup_value(v: *Variant, key: [*:0]const u8, expected: ?*const VariantType) ?*Variant;
pub extern fn g_variant_is_of_type(v: *Variant, t: *const VariantType) c_int;
pub extern fn g_variant_get_type_string(v: *Variant) [*:0]const u8;
pub extern fn g_variant_ref_sink(v: *Variant) *Variant;
pub extern fn g_variant_unref(v: *Variant) void;
pub extern fn g_variant_print(v: *Variant, type_annotate: c_int) [*:0]u8;

pub extern fn g_main_loop_new(ctx: ?*MainContext, is_running: c_int) *MainLoop;
pub extern fn g_main_loop_run(loop: *MainLoop) void;
pub extern fn g_main_loop_quit(loop: *MainLoop) void;
pub extern fn g_unix_fd_add_full(
    priority: c_int,
    fd: c_int,
    condition: c_int,
    function: UnixFdSourceFunc,
    user_data: ?*anyopaque,
    notify: ?*const anyopaque,
) c_uint;
pub extern fn g_timeout_add(interval_ms: c_uint, function: *const fn (?*anyopaque) callconv(.c) c_int, data: ?*anyopaque) c_uint;

// ── Thin Zig-side helpers ─────────────────────────────────────────────────────

/// Type string of a variant, as a Zig slice.
pub fn typeString(v: *Variant) []const u8 {
    return std.mem.span(g_variant_get_type_string(v));
}

/// True when the variant's type string matches exactly.
pub fn isType(v: *Variant, sig: []const u8) bool {
    return std.mem.eql(u8, typeString(v), sig);
}

/// Child `i` of a container. The caller owns a reference.
pub fn child(v: *Variant, i: usize) *Variant {
    return g_variant_get_child_value(v, i);
}

/// String contents of an `s`/`o`/`g` variant, valid while `v` lives.
pub fn str(v: *Variant) []const u8 {
    return std.mem.span(g_variant_get_string(v, null));
}

/// Unwraps a `v` box; returns the variant itself otherwise. Caller owns a ref.
pub fn unbox(v: *Variant) *Variant {
    if (isType(v, "v")) return child(v, 0);
    return g_variant_ref_sink(v);
}

/// Looks up `key` in an a{sv} dictionary and unboxes the value.
/// Caller owns the returned reference.
pub fn dictLookup(dict: *Variant, key: [*:0]const u8) ?*Variant {
    const boxed = g_variant_lookup_value(dict, key, null) orelse return null;
    defer g_variant_unref(boxed);
    return unbox(boxed);
}

/// An empty `a{sv}`, for the platform-data argument of org.gtk.Actions.
pub fn emptyAsv() *Variant {
    const t = g_variant_type_new("{sv}");
    defer g_variant_type_free(t);
    return g_variant_new_array(t, null, 0);
}

pub fn newTuple(children: []const *Variant) *Variant {
    return g_variant_new_tuple(if (children.len == 0) null else children.ptr, children.len);
}

pub fn newVariantArray(children: []const *Variant) *Variant {
    const t = g_variant_type_new("v");
    defer g_variant_type_free(t);
    return g_variant_new_array(t, if (children.len == 0) null else children.ptr, children.len);
}

pub fn newStringArray(children: []const *Variant) *Variant {
    const t = g_variant_type_new("s");
    defer g_variant_type_free(t);
    return g_variant_new_array(t, if (children.len == 0) null else children.ptr, children.len);
}

pub fn newU32Array(children: []const *Variant) *Variant {
    const t = g_variant_type_new("u");
    defer g_variant_type_free(t);
    return g_variant_new_array(t, if (children.len == 0) null else children.ptr, children.len);
}

pub fn newI32Array(children: []const *Variant) *Variant {
    const t = g_variant_type_new("i");
    defer g_variant_type_free(t);
    return g_variant_new_array(t, if (children.len == 0) null else children.ptr, children.len);
}

/// A blocking method call that swallows D-Bus errors: every caller here treats
/// "the app did not answer" the same as "the app has no menu".
pub fn callSync(
    conn: *Connection,
    bus: [*:0]const u8,
    path: [*:0]const u8,
    iface: [*:0]const u8,
    method: [*:0]const u8,
    params: ?*Variant,
    timeout_ms: c_int,
) ?*Variant {
    var err: ?*Error = null;
    const reply = g_dbus_connection_call_sync(
        conn,
        bus,
        path,
        iface,
        method,
        params,
        null,
        CALL_FLAGS_NO_AUTO_START,
        timeout_ms,
        null,
        &err,
    );
    if (reply == null) {
        if (err) |e| g_error_free(e);
        return null;
    }
    return reply;
}
