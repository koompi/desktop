const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // ReleaseSafe by default, so the shipped binary keeps overflow and bounds
    // checks the way globalmenu/Cargo.toml keeps `overflow-checks` in release.
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Prioritize performance, safety, or binary size",
    ) orelse .ReleaseSafe;

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.link_libc = true;
    // pipewire/conf.h drags in spa/utils/json-core.h, whose SPA_FLAG_CLEAR static
    // assertion translate-c cannot fold; clang, gcc and `zig cc` all compile the
    // same header. Predefining the guard skips it, and audiod calls no pw_conf_*.
    mod.addCMacro("PIPEWIRE_CONF_H", "1");
    mod.linkSystemLibrary("pipewire-0.3", .{});

    const exe = b.addExecutable(.{
        .name = "audiod",
        .root_module = mod,
    });
    b.installArtifact(exe);

    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the audiod unit tests").dependOn(&run_tests.step);

    const run_command = b.addRunArtifact(exe);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_command.addArgs(args);
    b.step("run", "Run audiod").dependOn(&run_command.step);
}
