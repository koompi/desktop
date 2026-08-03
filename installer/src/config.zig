//! config.zig - the accumulated answers from the TUI.
//!
//! SCAFFOLD. InstallConfig is what the TUI fills in step by step and archinstall.zig
//! serializes. Strings are borrowed slices for the skeleton; a real build must decide
//! ownership, most likely a TUI-owned arena. Marked TODO where it matters.

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
    locale: []const u8 = "en_US.UTF-8",
    timezone: []const u8 = "Asia/Phnom_Penh", // KOOMPI default; TUI can change
    keymap: []const u8 = "us",

    // The WHOLE disk archinstall will wipe + partition. e.g. "/dev/nvme0n1".
    // TODO: real enumeration in main.zig populates the picker; this is the
    // chosen result. Empty == not yet chosen (Review must block on it).
    disk_path: []const u8 = "",

    hostname: []const u8 = "koompi",
    username: []const u8 = "",

    // SECRET, and deliberately not a casual field on a long-lived copyable struct. The
    // TUI should hand it straight to the credential serializer. Never log it.
    // TODO(security): replace this placeholder slot with a wiped/locked buffer, cleared
    // once creds are written.
    password: []const u8 = "", // <-- secret; do not persist or log

    edition: Edition = .hyprland,

    encrypt: bool = false, // LUKS full-disk; archinstall owns the actual LUKS
    btrfs: bool = true, //    btrfs + subvolumes is the KOOMPI default layout

    /// Cheap completeness gate for the Review step. NOT validation of contents
    /// (that's archinstall's job) - just "did the user answer the required
    /// questions". TODO: surface which field is missing in the TUI.
    pub fn isComplete(self: InstallConfig) bool {
        return self.disk_path.len != 0 and
            self.username.len != 0 and
            self.password.len != 0 and
            self.hostname.len != 0;
    }
};
