//! app.zig - installer state machine, raw-tty input, and per-screen handlers.
//!
//! The installer's linear-but-back-navigable steps. The state machine is just
//! "which screen are we on"; each screen mutates one slice of InstallConfig.

const std = @import("std");

const config = @import("config.zig");
const InstallConfig = config.InstallConfig;

pub const Step = enum {
    welcome,
    locale, //   locale + timezone + keymap
    disk,
    identity, // hostname + username + password
    edition,
    encrypt,
    review,
    run,
    done,

    /// Next screen in the forward flow. `review`/`run`/`done` are handled
    /// specially (review can jump back; run is terminal-ish).
    pub fn next(self: Step) Step {
        return switch (self) {
            .welcome => .locale,
            .locale => .disk,
            .disk => .identity,
            .identity => .edition,
            .edition => .encrypt,
            .encrypt => .review,
            .review => .run,
            .run => .done,
            .done => .done,
        };
    }

    pub fn prev(self: Step) Step {
        return switch (self) {
            .welcome => .welcome,
            .locale => .welcome,
            .disk => .locale,
            .identity => .disk,
            .edition => .identity,
            .encrypt => .edition,
            .review => .encrypt,
            .run => .review,
            .done => .done,
        };
    }

    pub fn title(self: Step) []const u8 {
        return switch (self) {
            .welcome => "Welcome to KOOMPI OS",
            .locale => "Language, timezone & keyboard",
            .disk => "Select a disk",
            .identity => "Your account",
            .edition => "Choose your edition",
            .encrypt => "Disk encryption",
            .review => "Review",
            .run => "Installing…",
            .done => "Done",
        };
    }
};

pub const all_steps = [_]Step{ .welcome, .locale, .disk, .identity, .edition, .encrypt, .review, .run, .done };

/// Whole-app state: where we are + everything we've collected so far.
pub const App = struct {
    alloc: std.mem.Allocator,
    step: Step = .welcome,
    cfg: InstallConfig = .{},
    should_quit: bool = false,

    pub fn goNext(self: *App) void {
        self.step = self.step.next();
    }
    pub fn goBack(self: *App) void {
        self.step = self.step.prev();
    }
};

// Event model.
pub const Action = enum { advance, back, quit, none };

/// Raw termios on stdin, restored on `deinit`. Fails open: if stdin isn't a
/// real tty (piped/non-interactive), `enable()` returns null and callers fall
/// back to the auto-advance stub behavior — same fail-open convention as
/// `cidata.detect`.
pub const RawMode = struct {
    orig: std.posix.termios,

    pub fn enable() ?RawMode {
        const fd = std.posix.STDIN_FILENO;
        var term = std.posix.tcgetattr(fd) catch return null;
        const orig = term;
        term.lflag.ICANON = false;
        term.lflag.ECHO = false;
        term.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        term.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        std.posix.tcsetattr(fd, .NOW, term) catch return null;
        return .{ .orig = orig };
    }

    pub fn disable(self: RawMode) void {
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, self.orig) catch {};
    }
};

fn readKey() Action {
    var buf: [1]u8 = undefined;
    const n = std.posix.read(std.posix.STDIN_FILENO, &buf) catch return .advance;
    if (n == 0) return .advance;
    return switch (buf[0]) {
        '\r', '\n' => .advance,
        0x1b => .back,
        0x03 => .quit,
        else => .none,
    };
}

pub fn nextAction(raw: ?RawMode) Action {
    if (raw == null) return .advance; // non-tty: auto-advance so the flow is inspectable
    return readKey();
}

// Per-screen logic. Each `handle*` is where that screen writes into app.cfg.
// The drawing is in `draw()`. These are where the real TUI widgets (text
// fields, the disk list, the edition radio) get wired up.

/// TODO: real device enumeration. Options:
///   - parse `lsblk -J -d -o NAME,SIZE,MODEL,TYPE` (filter type=="disk")
///   - or read /sys/block/*/{size,device/model,removable}
/// Return a list the TUI renders as a selectable menu. Hardcoded for the skeleton.
fn enumerateDisks(alloc: std.mem.Allocator) []const []const u8 {
    _ = alloc;
    // PLACEHOLDER - no real probing. REVIEW before this ever drives a wipe.
    return &.{ "/dev/nvme0n1", "/dev/sda" };
}

pub fn handleDisk(app: *App) void {
    const disks = enumerateDisks(app.alloc);
    // TODO: let the user pick from `disks`; capture selection. Skeleton takes [0].
    if (disks.len != 0) app.cfg.disk_path = disks[0];
}

pub fn handleIdentity(app: *App) void {
    // TODO: text fields for hostname / username / password.
    // SECURITY: the password field must be masked, and the captured secret
    // should go straight toward archinstall.writeUserCredentials - see the note
    // in config.zig. Do NOT echo or log it.
    if (app.cfg.username.len == 0) app.cfg.username = "koompi"; // placeholder
    // app.cfg.password = <captured secret>;  // TODO
}

pub fn handleEdition(app: *App) void {
    // TODO: radio between the two editions; capture selection.
    // Defaults to .hyprland (config.zig). The enum -> package mapping lives in
    // archinstall.targetPackage(), so this screen only sets the enum.
    _ = app;
}

pub fn handleEncrypt(app: *App) void {
    // TODO: yes/no toggle. archinstall owns the actual LUKS.
    _ = app;
}
