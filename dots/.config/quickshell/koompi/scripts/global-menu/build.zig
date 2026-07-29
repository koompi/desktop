const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    // GDBus, for the AppMenu registrar we serve and the menu calls we make.
    mod.link_libc = true;
    mod.linkSystemLibrary("gio-2.0", .{});
    mod.linkSystemLibrary("glib-2.0", .{});
    mod.linkSystemLibrary("gobject-2.0", .{});

    const exe = b.addExecutable(.{
        .name = "global-menu-daemon",
        .root_module = mod,
    });
    b.installArtifact(exe);

    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the daemon unit tests").dependOn(&run_tests.step);
}
