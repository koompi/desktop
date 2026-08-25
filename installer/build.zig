// KOOMPI installer — build script (Zig 0.14+ build API; src/ needs 0.14.x std).
//
// Declares the `koompi-installer` executable. No dependencies — rendering is
// direct ANSI, not libvaxis; see build.zig.zon.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "koompi-installer",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    // `zig build run` → launch the TUI.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the KOOMPI installer");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{ .root_module = root_module });
    const run_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
