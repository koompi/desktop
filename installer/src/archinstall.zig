//! archinstall.zig - the orchestration layer.
//!
//! SCAFFOLD, no real disk ops. Serializes InstallConfig into user_configuration.json
//! and user_credentials.json, execs `archinstall --config .. --creds .. --silent`,
//! then runs src/post_install.sh in the chroot. archinstall owns partition, LUKS,
//! pacstrap, GRUB and btrfs; every step here that touches a disk or a secret is
//! marked TODO/REVIEW.

const std = @import("std");
const config = @import("config.zig");
const InstallConfig = config.InstallConfig;
const Edition = config.Edition;

// archinstall's JSON schema drifts between releases. The ISO MUST pin this exact
// version, and a bump means re-checking every serializer below in the same change.
//
// Hand-writing the JSON is the wrong strategy and the literals below are shape
// templates, not a runnable config: disk_config needs per-partition obj_id UUIDs and
// size/start objects only archinstall can mint. Produce both files from the pinned
// release's `--dry-run`/save-config and parameterize them.
pub const ARCHINSTALL_VERSION = "4.x"; // TODO: pin the exact release on the ISO

/// The post-install chroot hook, kept as ONE source of truth via @embedFile so
/// the shell script and this "string constant" can never drift apart.
pub const POST_INSTALL_HOOK: []const u8 = @embedFile("post_install.sh");

/// Edition -> target metapackage. A `switch` so the mapping is impossible to get
/// wrong (verified against sdata/dist-arch/koompi-desktop-*).
pub fn targetPackage(edition: Edition) []const u8 {
    return switch (edition) {
        .hyprland => "koompi-desktop-hyprland",
        .kde => "koompi-desktop-kde",
    };
}

// Where the two files land on the live ISO. Credentials go on tmpfs (RAM only).
const CONFIG_PATH = "/tmp/koompi/user_configuration.json";
const CREDS_PATH = "/dev/shm/koompi_user_credentials.json"; // tmpfs/RAM — secret
const HOOK_PATH = "/tmp/koompi/post_install.sh";

// (a) SERIALIZE

/// Emit user_configuration.json. NON-SECRET - no passwords here.
///
/// REVIEW: hand-rolls the shape against ARCHINSTALL_VERSION. The btrfs subvolume
/// list, the disk_config/disk_layouts key and the package field name are the parts
/// that drift; diff the literal against the pinned archinstall's own example.
pub fn writeUserConfiguration(alloc: std.mem.Allocator, cfg: InstallConfig) !void {
    try std.fs.cwd().makePath(std.fs.path.dirname(CONFIG_PATH).?);
    const file = try std.fs.cwd().createFile(CONFIG_PATH, .{ .truncate = true });
    defer file.close();
    var bw = std.io.bufferedWriter(file.writer());
    const w = bw.writer();

    // TODO: replace this hand-written blob with archinstall's real schema for the
    // pinned version. The structure below is illustrative, not verified.
    const pkg = targetPackage(cfg.edition);
    _ = alloc;

    try w.print(
        \\{{
        \\  "_meta": {{
        \\    "generated_by": "koompi-installer (SCAFFOLD)",
        \\    "archinstall_version": "{s}"
        \\  }},
        \\
        \\  "bootloader_config": {{ "bootloader": "Grub", "uki": false }},
        \\  "kernels": ["linux"],
        \\
        \\  "locale_config": {{
        \\    "sys_lang": "{s}",
        \\    "sys_enc": "UTF-8",
        \\    "kb_layout": "{s}"
        \\  }},
        \\  "timezone": "{s}",
        \\
        \\  "hostname": "{s}",
        \\
        \\  "// disk_config": "BLOCKER/REVIEW: the SHAPE below is the real archinstall schema (config_type + device_modifications[].partitions[], with btrfs subvols NESTED under the root partition's `btrfs` key). But the concrete partition objects — obj_id UUIDs and exact size/start — MUST be produced by `archinstall --dry-run`/save-config of the PINNED release; they cannot be hand-fabricated. The old flat {{device,filesystem,encrypt,btrfs_subvolumes}} shape was SILENTLY IGNORED (archinstall reads device_modifications), so under --silent disk setup was a no-op.",
        \\  "disk_config": {{
        \\    "config_type": "manual_partitioning",
        \\    "device_modifications": [
        \\      {{
        \\        "device": "{s}",
        \\        "wipe": true,
        \\        "partitions": [
        \\          {{
        \\            "// REVIEW": "EFI system partition — obj_id/size come from archinstall save-config",
        \\            "obj_id": "<GENERATED-UUID>",
        \\            "status": "create",
        \\            "type": "primary",
        \\            "fs_type": "fat32",
        \\            "size": {{ "unit": "MiB", "value": 512 }},
        \\            "start": {{ "unit": "MiB", "value": 1 }},
        \\            "mountpoint": "/boot",
        \\            "flags": ["boot", "esp"]
        \\          }},
        \\          {{
        \\            "// REVIEW": "root partition holds the btrfs @ layout; its OWN mountpoint is null",
        \\            "obj_id": "<GENERATED-UUID>",
        \\            "status": "create",
        \\            "type": "primary",
        \\            "fs_type": "{s}",
        \\            "size": {{ "unit": "Percent", "value": 100 }},
        \\            "start": {{ "unit": "MiB", "value": 513 }},
        \\            "mountpoint": null,
        \\            "btrfs": [
        \\              {{ "name": "@",          "mountpoint": "/" }},
        \\              {{ "name": "@home",      "mountpoint": "/home" }},
        \\              {{ "name": "@var_log",   "mountpoint": "/var/log" }},
        \\              {{ "name": "@var_cache", "mountpoint": "/var/cache" }},
        \\              {{ "name": "@snapshots", "mountpoint": "/.snapshots" }}
        \\            ]
        \\          }}
        \\        ]
        \\      }}
        \\    ]
        \\  }},
        \\  "// disk_encryption": "LUKS is a SEPARATE top-level block (disk_encryption), NOT an encrypt field inside disk_config. Encryption requested: {s}. When true, add a top-level disk_encryption block of encryption_type luks that lists the root partition obj_id.",
        \\
        \\  "// packages": "the chosen KOOMPI edition metapackage drives everything else",
        \\  "packages": ["{s}"],
        \\
        \\  "// custom_commands": "post-install runs separately via runPostInstallHook()"
        \\}}
        \\
    , .{
        ARCHINSTALL_VERSION,
        cfg.locale,
        cfg.keymap,
        cfg.timezone,
        cfg.hostname,
        cfg.disk_path,
        if (cfg.btrfs) "btrfs" else "ext4",
        if (cfg.encrypt) "yes" else "no",
        pkg,
    });

    try bw.flush();
}

/// Emit user_credentials.json. SECRET: root + user passwords. Written to tmpfs,
/// chmod 600, shredded by cleanupCredentials() the moment archinstall exits, never
/// logged.
///
/// TODO(security): the password rides on InstallConfig as a plain slice. Replace
/// with a locked/zeroed buffer passed straight here.
pub fn writeUserCredentials(alloc: std.mem.Allocator, cfg: InstallConfig) !void {
    _ = alloc;
    const file = try std.fs.cwd().createFile(CREDS_PATH, .{
        .truncate = true,
        .mode = 0o600, // owner read/write only
    });
    defer file.close();
    var bw = std.io.bufferedWriter(file.writer());
    const w = bw.writer();

    // Keys verified against archinstall source, both easy to get wrong:
    //   a user's plaintext key is "!password", not "password". A bare "password" is read
    //   by neither parser branch, so the user is silently skipped and never created.
    //   root accepts only "root_enc_password" (a hash), so root stays LOCKED and the
    //   sudo user is the way in.
    // Do not log this writer's input.
    // TODO(security): generate creds via the pinned archinstall so the password is
    // hashed and never written as plaintext, even to tmpfs.
    try w.print(
        \\{{
        \\  "// root": "root is intentionally left LOCKED (no password); admin access is via the sudo user below. archinstall reads only root_enc_password (a HASH) and has no plaintext root key, so we omit it rather than ship an unhashable value. To set a root password, generate creds via the pinned archinstall (it hashes and emits root_enc_password).",
        \\  "users": [
        \\    {{
        \\      "username": "{s}",
        \\      "!password": "{s}",
        \\      "sudo": true,
        \\      "groups": []
        \\    }}
        \\  ]
        \\}}
        \\
    , .{ cfg.username, cfg.password });

    try bw.flush();
}

/// Shred the credentials file. Call in a `defer` right after the archinstall
/// exec so a secret never survives the process - even on an error path.
/// TODO: overwrite-then-unlink (or rely on tmpfs being RAM-only) before delete.
pub fn cleanupCredentials() void {
    std.fs.cwd().deleteFile(CREDS_PATH) catch {};
}

// (b) EXEC archinstall

/// Run `archinstall --config … --creds … --silent`. This is the call that does
/// the destructive install. ⚠️ TODO/REVIEW: guarded behind the Review screen in
/// main.zig; must not be reachable without an explicit confirmation.
pub fn runArchinstall(alloc: std.mem.Allocator) !void {
    var child = std.process.Child.init(&.{
        "archinstall",
        "--config",
        CONFIG_PATH,
        "--creds",
        CREDS_PATH,
        "--silent",
    }, alloc);
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.ArchinstallFailed,
        else => return error.ArchinstallTerminatedAbnormally,
    }
}

// (c) POST-INSTALL CHROOT HOOK

/// Drop post_install.sh onto the live ISO and run it in the target via arch-chroot.
///
/// TODO/REVIEW: hard-codes the target mount at /mnt, archinstall's default. Confirm
/// it against the pinned release.
pub fn runPostInstallHook(alloc: std.mem.Allocator) !void {
    try std.fs.cwd().makePath(std.fs.path.dirname(HOOK_PATH).?);
    {
        const f = try std.fs.cwd().createFile(HOOK_PATH, .{
            .truncate = true,
            .mode = 0o755,
        });
        defer f.close();
        try f.writeAll(POST_INSTALL_HOOK); // single source of truth (@embedFile)
    }

    // Copy the script into the target and run it under chroot.
    // REVIEW: target root assumed at /mnt; script path inside target is /root/.
    const target_root = "/mnt";
    {
        var cp = std.process.Child.init(
            &.{ "cp", HOOK_PATH, target_root ++ "/root/post_install.sh" },
            alloc,
        );
        const cp_term = try cp.spawnAndWait();
        switch (cp_term) {
            .Exited => |code| if (code != 0) return error.CopyHookFailed,
            else => return error.CopyHookTerminatedAbnormally,
        }
    }

    var chroot = std.process.Child.init(
        &.{ "arch-chroot", target_root, "/bin/bash", "/root/post_install.sh" },
        alloc,
    );
    chroot.stdin_behavior = .Inherit;
    chroot.stdout_behavior = .Inherit;
    chroot.stderr_behavior = .Inherit;

    const term = try chroot.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.PostInstallFailed,
        else => return error.PostInstallTerminatedAbnormally,
    }
}

// Top-level orchestration: the full sequence Review->Run calls.

/// The whole destructive sequence, in order, with the credential file shredded
/// no matter how we leave. ⚠️ Only call after an explicit Review confirmation.
pub fn run(alloc: std.mem.Allocator, cfg: InstallConfig) !void {
    try writeUserConfiguration(alloc, cfg);

    // Register the shred BEFORE the creds write. A `defer` only fires if control reached
    // it, so one placed after writeUserCredentials would never register if that throws
    // mid-write, and the plaintext would persist on tmpfs.
    defer cleanupCredentials();
    try writeUserCredentials(alloc, cfg);

    try runArchinstall(alloc); // ⚠️ destructive — archinstall owns it

    // archinstall is the ONLY consumer of the creds file; shred it eagerly the
    // moment it exits so the plaintext's RAM lifetime ends here - NOT minutes
    // later after the chroot hook. cleanupCredentials() swallows ENOENT, so this
    // is idempotent and the defer above stays as a backstop for the error paths.
    cleanupCredentials();

    try runPostInstallHook(alloc); // finishing touches in the chroot
}
