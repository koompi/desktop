// KOOMPI installer — build script (Zig 0.14.x).
//
// SCAFFOLD: declares a single `koompi-installer` executable and wires in libvaxis.
// Idiomatic, minimal. See build.zig.zon for the dependency + placeholder hash.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Pull in the libvaxis dependency declared in build.zig.zon.
    // `.module("vaxis")` is the module name libvaxis exposes (verified against
    // its build.zig: `b.addModule("vaxis", ...)`).
    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "koompi-installer",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Downstream code does `@import("vaxis")`.
    exe.root_module.addImport("vaxis", vaxis.module("vaxis"));

    b.installArtifact(exe);

    // `zig build run` → launch the (skeleton) TUI.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the KOOMPI installer (SCAFFOLD)");
    run_step.dependOn(&run_cmd.step);
}
