//! config.zig — the accumulated answers from the TUI.
//!
//! SCAFFOLD. `InstallConfig` is the single source of truth that the TUI fills
//! in step by step and that `archinstall.zig` serializes into the two JSON
//! files archinstall consumes.
//!
//! NOTE ON STRINGS: these are borrowed slices for the skeleton. A real build
//! must decide ownership (most will point into a TUI-owned arena that lives as
//! long as the config). Marked TODO where it matters.

const std = @import("std");

/// The two installer-selectable KOOMPI editions. The enum -> target package
/// mapping lives in archinstall.zig as a `switch` so it cannot drift.
pub const Edition = enum {
    hyprland, // -> koompi-desktop-hyprland
    kde, //      -> koompi-desktop-kde

    pub fn label(self: Edition) []const u8 {
        return switch (self) {
            .hyprland => "KOOMPI Hyprland",
            .kde => "KOOMPI KDE",
        };
    }
};

pub const InstallConfig = struct {
    // ── Locale / region ───────────────────────────────────────────────────
    locale: []const u8 = "en_US.UTF-8",
    timezone: []const u8 = "Asia/Phnom_Penh", // KOOMPI default; TUI can change
    keymap: []const u8 = "us",

    // ── Target disk ───────────────────────────────────────────────────────
    // The WHOLE disk archinstall will wipe + partition. e.g. "/dev/nvme0n1".
    // TODO: real enumeration in main.zig populates the picker; this is the
    // chosen result. Empty == not yet chosen (Review must block on it).
    disk_path: []const u8 = "",

    // ── Identity ──────────────────────────────────────────────────────────
    hostname: []const u8 = "koompi",
    username: []const u8 = "",

    // PASSWORD HANDLING — SECRET. We deliberately do NOT store the password as a
    // casual field on a long-lived, copyable struct. It belongs in
    // `user_credentials.json`, which archinstall.zig writes to tmpfs, chmod 600,
    // and DELETES immediately after archinstall exits. Never log it. The TUI
    // hands the password straight to the credential serializer; it should not
    // linger in InstallConfig. The field below is a placeholder slot ONLY so the
    // skeleton type-checks — REVIEW: replace with a zero-on-free secret buffer.
    // TODO(security): use a wiped/locked buffer; clear after creds are written.
    password: []const u8 = "", // <-- secret; do not persist or log

    // ── Edition ───────────────────────────────────────────────────────────
    edition: Edition = .hyprland,

    // ── Disk options ──────────────────────────────────────────────────────
    encrypt: bool = false, // LUKS full-disk; archinstall owns the actual LUKS
    btrfs: bool = true, //    btrfs + subvolumes is the KOOMPI default layout

    /// Cheap completeness gate for the Review step. NOT validation of contents
    /// (that's archinstall's job) — just "did the user answer the required
    /// questions". TODO: surface which field is missing in the TUI.
    pub fn isComplete(self: InstallConfig) bool {
        return self.disk_path.len != 0 and
            self.username.len != 0 and
            self.password.len != 0 and
            self.hostname.len != 0;
    }
};
