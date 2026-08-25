//! cidata.zig - detect a cidata-labeled seed drive and pre-fill InstallConfig for an
//! unattended install (cloud-init's NoCloud "cidata" convention: a drive labeled
//! `cidata` carrying user_configuration.json plus either user_credentials.json or a
//! defer-provisioning marker).
//!
//! Must fail open: any missing or malformed piece returns `.none` and falls back to
//! the interactive wizard rather than half-trusting a drive.

const std = @import("std");
const config = @import("config.zig");
const InstallConfig = config.InstallConfig;
const Edition = config.Edition;

pub const ProvisionMode = enum { none, configured, deferred };

const MOUNT_POINT = "/mnt/cidata";
const CONFIG_FILE = "user_configuration.json";
const CREDS_FILE = "user_credentials.json";
const DEFER_MARKER = "defer-provisioning";

/// Full pipeline: find the device, mount it read-only, hand the mounted root to
/// `detectFromRoot`, unmount. Any failure before the mount succeeds is fail-open
/// (`.none`); once mounted, `detectFromRoot` owns fail-open for its own errors.
pub fn detect(alloc: std.mem.Allocator, io: std.Io, cfg: *InstallConfig) !ProvisionMode {
    const dev = (try findDevice(alloc, io)) orelse return .none;
    defer alloc.free(dev);

    try std.Io.Dir.cwd().createDirPath(io, MOUNT_POINT);
    mountReadOnly(io, dev) catch |err| {
        std.log.warn("cidata: mount {s} on {s} failed: {s}", .{ dev, MOUNT_POINT, @errorName(err) });
        return .none;
    };
    defer unmount(io);

    var dir = std.Io.Dir.openDirAbsolute(io, MOUNT_POINT, .{}) catch |err| {
        std.log.warn("cidata: open {s} failed: {s}", .{ MOUNT_POINT, @errorName(err) });
        return .none;
    };
    defer dir.close(io);

    return detectFromRoot(alloc, io, cfg, dir);
}

/// The testable core: everything below the mount. `dir` is the cidata root, real
/// or a fixture standing in for it.
pub fn detectFromRoot(alloc: std.mem.Allocator, io: std.Io, cfg: *InstallConfig, dir: std.Io.Dir) !ProvisionMode {
    const raw = dir.readFileAlloc(io, CONFIG_FILE, alloc, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .none,
        else => return err,
    };
    defer alloc.free(raw);

    parseUserConfiguration(alloc, cfg, raw) catch |err| {
        std.log.err("cidata: malformed {s}: {s}", .{ CONFIG_FILE, @errorName(err) });
        return .none;
    };

    if (dir.readFileAlloc(io, CREDS_FILE, alloc, .limited(16 * 1024))) |creds_raw| {
        defer alloc.free(creds_raw);
        parseUserCredentials(alloc, cfg, creds_raw) catch |err| {
            std.log.err("cidata: malformed {s}: {s}", .{ CREDS_FILE, @errorName(err) });
            return .none;
        };
        return .configured;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    dir.access(io, DEFER_MARKER, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.err(
                "cidata: {s} present but neither {s} nor {s} found - malformed drive, ignoring",
                .{ CONFIG_FILE, CREDS_FILE, DEFER_MARKER },
            );
            return .none;
        },
        else => return err,
    };
    cfg.defer_provisioning = true;
    return .deferred;
}

// mirrors InstallConfig's defaults for the fields this file may legitimately omit;
// keep in sync if InstallConfig's defaults change.
const UserConfigurationJson = struct {
    locale: []const u8 = "en_US.UTF-8",
    timezone: []const u8 = "Asia/Phnom_Penh",
    keymap: []const u8 = "us",
    hostname: []const u8 = "koompi",
    disk_path: []const u8 = "",
    edition: Edition = .hyprland,
    encrypt: bool = false,
    btrfs: bool = true,
};

fn parseUserConfiguration(alloc: std.mem.Allocator, cfg: *InstallConfig, raw: []const u8) !void {
    const parsed = try std.json.parseFromSlice(UserConfigurationJson, alloc, raw, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const v = parsed.value;

    cfg.locale = try alloc.dupe(u8, v.locale);
    cfg.timezone = try alloc.dupe(u8, v.timezone);
    cfg.keymap = try alloc.dupe(u8, v.keymap);
    cfg.hostname = try alloc.dupe(u8, v.hostname);
    cfg.disk_path = try alloc.dupe(u8, v.disk_path);
    cfg.edition = v.edition;
    cfg.encrypt = v.encrypt;
    cfg.btrfs = v.btrfs;
}

const UserCredentialsJson = struct {
    username: []const u8,
    password: []const u8,
};

fn parseUserCredentials(alloc: std.mem.Allocator, cfg: *InstallConfig, raw: []const u8) !void {
    const parsed = try std.json.parseFromSlice(UserCredentialsJson, alloc, raw, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    cfg.username = try alloc.dupe(u8, parsed.value.username);
    cfg.password = try alloc.dupe(u8, parsed.value.password);
}

fn findDevice(alloc: std.mem.Allocator, io: std.Io) !?[]const u8 {
    if (try blkidDevice(alloc, io)) |dev| return dev;
    return lsblkDevice(alloc, io);
}

fn blkidDevice(alloc: std.mem.Allocator, io: std.Io) !?[]const u8 {
    const result = std.process.run(alloc, io, .{
        .argv = &.{ "blkid", "-L", "cidata" },
    }) catch return null;
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);

    const trimmed = std.mem.trim(u8, result.stdout, " \t\r\n");
    if (trimmed.len == 0) return null;
    return try alloc.dupe(u8, trimmed);
}

const LsblkDevice = struct {
    name: []const u8,
    label: ?[]const u8 = null,
    children: []const LsblkDevice = &.{},
};
const LsblkOutput = struct {
    blockdevices: []const LsblkDevice = &.{},
};

fn lsblkDevice(alloc: std.mem.Allocator, io: std.Io) !?[]const u8 {
    const result = std.process.run(alloc, io, .{
        .argv = &.{ "lsblk", "-J", "-o", "NAME,LABEL" },
        .stdout_limit = .limited(256 * 1024),
    }) catch return null;
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);

    const parsed = std.json.parseFromSlice(LsblkOutput, alloc, result.stdout, .{ .ignore_unknown_fields = true }) catch return null;
    defer parsed.deinit();

    const name = findCidataName(parsed.value.blockdevices) orelse return null;
    return try std.fmt.allocPrint(alloc, "/dev/{s}", .{name});
}

// lsblk -J nests partitions under their parent disk as "children"; walk both levels.
fn findCidataName(devices: []const LsblkDevice) ?[]const u8 {
    for (devices) |d| {
        if (d.label) |label| {
            if (std.mem.eql(u8, label, "cidata")) return d.name;
        }
        if (findCidataName(d.children)) |name| return name;
    }
    return null;
}

fn mountReadOnly(io: std.Io, dev: []const u8) !void {
    var child = try std.process.spawn(io, .{ .argv = &.{ "mount", "-o", "ro,nosuid,nodev", dev, MOUNT_POINT } });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.MountFailed,
        else => return error.MountFailed,
    }
}

fn unmount(io: std.Io) void {
    var child = std.process.spawn(io, .{ .argv = &.{ "umount", MOUNT_POINT } }) catch |err| {
        std.log.warn("cidata: umount {s} failed: {s}", .{ MOUNT_POINT, @errorName(err) });
        return;
    };
    _ = child.wait(io) catch |err| {
        std.log.warn("cidata: umount {s} failed: {s}", .{ MOUNT_POINT, @errorName(err) });
    };
}

test "no cidata present -> .none" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var cfg = InstallConfig{};
    const mode = try detectFromRoot(alloc, io, &cfg, tmp.dir);
    try std.testing.expectEqual(ProvisionMode.none, mode);
}

test "user_configuration.json + user_credentials.json -> .configured with parsed fields" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{
        .sub_path = CONFIG_FILE,
        .data =
        \\{
        \\  "locale": "km_KH.UTF-8",
        \\  "timezone": "Asia/Phnom_Penh",
        \\  "keymap": "kh",
        \\  "hostname": "koompi-oem",
        \\  "disk_path": "/dev/nvme0n1",
        \\  "edition": "kde",
        \\  "encrypt": true,
        \\  "btrfs": false
        \\}
        ,
    });
    try tmp.dir.writeFile(io, .{
        .sub_path = CREDS_FILE,
        .data =
        \\{ "username": "rithy", "password": "s3cr3t" }
        ,
    });

    var cfg = InstallConfig{};
    const mode = try detectFromRoot(alloc, io, &cfg, tmp.dir);
    defer alloc.free(cfg.locale);
    defer alloc.free(cfg.timezone);
    defer alloc.free(cfg.keymap);
    defer alloc.free(cfg.hostname);
    defer alloc.free(cfg.disk_path);
    defer alloc.free(cfg.username);
    defer alloc.free(cfg.password);

    try std.testing.expectEqual(ProvisionMode.configured, mode);
    try std.testing.expectEqualStrings("km_KH.UTF-8", cfg.locale);
    try std.testing.expectEqualStrings("kh", cfg.keymap);
    try std.testing.expectEqualStrings("koompi-oem", cfg.hostname);
    try std.testing.expectEqualStrings("/dev/nvme0n1", cfg.disk_path);
    try std.testing.expectEqual(Edition.kde, cfg.edition);
    try std.testing.expect(cfg.encrypt);
    try std.testing.expect(!cfg.btrfs);
    try std.testing.expectEqualStrings("rithy", cfg.username);
    try std.testing.expectEqualStrings("s3cr3t", cfg.password);
    try std.testing.expect(!cfg.defer_provisioning);
}

test "user_configuration.json + defer-provisioning marker -> .deferred" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{
        .sub_path = CONFIG_FILE,
        .data =
        \\{ "hostname": "koompi-oem", "disk_path": "/dev/sda" }
        ,
    });
    try tmp.dir.writeFile(io, .{ .sub_path = DEFER_MARKER, .data = "" });

    var cfg = InstallConfig{};
    const mode = try detectFromRoot(alloc, io, &cfg, tmp.dir);
    defer alloc.free(cfg.hostname);
    defer alloc.free(cfg.disk_path);
    defer alloc.free(cfg.locale);
    defer alloc.free(cfg.timezone);
    defer alloc.free(cfg.keymap);

    try std.testing.expectEqual(ProvisionMode.deferred, mode);
    try std.testing.expect(cfg.defer_provisioning);
    try std.testing.expectEqualStrings("", cfg.username);
    try std.testing.expectEqualStrings("", cfg.password);
}

test "cidata label present but user_configuration.json missing -> .none (fail open)" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // simulates a drive that mounted fine (right label) but wasn't a real seed.
    try tmp.dir.writeFile(io, .{ .sub_path = "README.txt", .data = "not a seed drive" });

    var cfg = InstallConfig{};
    const mode = try detectFromRoot(alloc, io, &cfg, tmp.dir);
    try std.testing.expectEqual(ProvisionMode.none, mode);
}
