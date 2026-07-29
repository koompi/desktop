//! main.zig — KOOMPI installer TUI (the "face").
//!
//! ⚠️ SCAFFOLD. The substance here is the STATE MACHINE and how answers
//! accumulate into an InstallConfig. The libvaxis draw loop + event handling
//! are intentionally STUBBED (clearly-marked TODOs) — getting the vaxis event
//! loop subtly wrong would distract from the skeleton's real job. This may not
//! fully compile against a specific libvaxis revision; that is acceptable per
//! the scaffold's scope.
//!
//! Flow:
//!   Welcome → Locale/Timezone/Keyboard → Disk → User/Hostname → Edition
//!           → Encrypt → Review → Run
//!
//! Render: a placeholder draw loop. Real device enumeration and real vaxis
//! event handling are marked TODO where they go.

const std = @import("std");
const vaxis = @import("vaxis"); // libvaxis — see build.zig.zon (placeholder hash)

const config = @import("config.zig");
const InstallConfig = config.InstallConfig;
const Edition = config.Edition;
const archinstall = @import("archinstall.zig");

/// The installer's linear-but-back-navigable steps. The state machine is just
/// "which screen are we on"; each screen mutates one slice of InstallConfig.
const Step = enum {
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
    fn next(self: Step) Step {
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

    fn prev(self: Step) Step {
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

    fn title(self: Step) []const u8 {
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

/// Whole-app state: where we are + everything we've collected so far.
const App = struct {
    alloc: std.mem.Allocator,
    step: Step = .welcome,
    cfg: InstallConfig = .{},
    should_quit: bool = false,

    // TODO: hold the vaxis instance + tty + event loop here in a real build:
    //   vx: vaxis.Vaxis,
    //   tty: vaxis.Tty,

    fn goNext(self: *App) void {
        self.step = self.step.next();
    }
    fn goBack(self: *App) void {
        self.step = self.step.prev();
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// Event model (placeholder).
// In a real libvaxis app these come from `loop.nextEvent()`. We model only what
// the state machine reacts to; mapping raw vaxis.Key/Event -> Action is TODO.
// ─────────────────────────────────────────────────────────────────────────────
const Action = enum { advance, back, quit, none };

/// TODO: replace with real libvaxis event handling. Sketch:
///   const event = loop.nextEvent();
///   switch (event) {
///     .key_press => |key| {
///        if (key.matches('c', .{ .ctrl = true })) return .quit;
///        if (key.matches(vaxis.Key.enter, .{}))    return .advance;
///        if (key.matches(vaxis.Key.escape, .{}))   return .back;
///        // …per-screen text input, list selection, etc.
///     },
///     .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
///   }
/// Each screen also needs to capture text/selection into App.cfg here.
fn nextAction(app: *App) Action {
    _ = app;
    // STUB: a real loop blocks on input. The skeleton just signals "advance"
    // so the flow is readable end-to-end without a live terminal.
    return .advance;
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-screen logic. Each `handle*` is where that screen writes into app.cfg.
// The drawing is stubbed in `draw()`. These are where the real TUI widgets
// (text fields, the disk list, the edition radio) get wired up.
// ─────────────────────────────────────────────────────────────────────────────

/// TODO: real device enumeration. Options:
///   - parse `lsblk -J -d -o NAME,SIZE,MODEL,TYPE` (filter type=="disk")
///   - or read /sys/block/*/{size,device/model,removable}
/// Return a list the TUI renders as a selectable menu. Hardcoded for the skeleton.
fn enumerateDisks(alloc: std.mem.Allocator) []const []const u8 {
    _ = alloc;
    // PLACEHOLDER — no real probing. REVIEW before this ever drives a wipe.
    return &.{ "/dev/nvme0n1", "/dev/sda" };
}

fn handleDisk(app: *App) void {
    const disks = enumerateDisks(app.alloc);
    // TODO: let the user pick from `disks`; capture selection. Skeleton takes [0].
    if (disks.len != 0) app.cfg.disk_path = disks[0];
}

fn handleIdentity(app: *App) void {
    // TODO: text fields for hostname / username / password.
    // SECURITY: the password field must be masked, and the captured secret
    // should go straight toward archinstall.writeUserCredentials — see the note
    // in config.zig. Do NOT echo or log it.
    if (app.cfg.username.len == 0) app.cfg.username = "koompi"; // placeholder
    // app.cfg.password = <captured secret>;  // TODO
}

fn handleEdition(app: *App) void {
    // TODO: radio between the two editions; capture selection.
    // Defaults to .hyprland (config.zig). The enum -> package mapping lives in
    // archinstall.targetPackage(), so this screen only sets the enum.
    _ = app;
}

fn handleEncrypt(app: *App) void {
    // TODO: yes/no toggle. archinstall owns the actual LUKS.
    _ = app;
}

// ─────────────────────────────────────────────────────────────────────────────
// Draw (placeholder). A real build draws into `vx.window()` and calls
// `vx.render(tty.anyWriter())`. Here we just print the screen so the flow is
// inspectable without a terminal.
// ─────────────────────────────────────────────────────────────────────────────
fn draw(app: *App) void {
    const out = std.io.getStdOut().writer();
    out.print("\n── {s} ──\n", .{app.step.title()}) catch {};

    switch (app.step) {
        .welcome => out.print(
            \\KOOMPI OS — Naga. This installer will set up your machine.
            \\[Enter] continue   [Ctrl-C] quit
            \\
        , .{}) catch {},

        .locale => out.print(
            "locale={s}  timezone={s}  keymap={s}   (TODO: pickers)\n",
            .{ app.cfg.locale, app.cfg.timezone, app.cfg.keymap },
        ) catch {},

        .disk => out.print(
            "target disk: {s}   (TODO: real lsblk enumeration + selection)\n",
            .{if (app.cfg.disk_path.len != 0) app.cfg.disk_path else "<none>"},
        ) catch {},

        .identity => out.print(
            "hostname={s}  username={s}  password=<hidden>   (TODO: masked fields)\n",
            .{ app.cfg.hostname, app.cfg.username },
        ) catch {},

        .edition => out.print(
            "edition: {s}   (TODO: radio Hyprland | KDE)\n",
            .{app.cfg.edition.label()},
        ) catch {},

        .encrypt => out.print(
            "encrypt (LUKS): {s}   (TODO: yes/no toggle)\n",
            .{if (app.cfg.encrypt) "yes" else "no"},
        ) catch {},

        .review => drawReview(app, out),

        .run => out.print("Running archinstall + post-install hook… (see logs)\n", .{}) catch {},
        .done => out.print("Installation complete. Reboot into KOOMPI OS.\n", .{}) catch {},
    }
}

fn drawReview(app: *App, out: anytype) void {
    const pkg = archinstall.targetPackage(app.cfg.edition);
    out.print(
        \\You are about to install:
        \\  edition  : {s}  ({s})
        \\  disk     : {s}   ⚠️ WILL BE ERASED
        \\  hostname : {s}
        \\  user     : {s}
        \\  locale   : {s}   timezone: {s}   keymap: {s}
        \\  encrypt  : {s}      filesystem: {s}
        \\
        \\[Enter] INSTALL (destructive)   [Esc] go back
        \\
    , .{
        app.cfg.edition.label(),
        pkg,
        app.cfg.disk_path,
        app.cfg.hostname,
        app.cfg.username,
        app.cfg.locale,
        app.cfg.timezone,
        app.cfg.keymap,
        if (app.cfg.encrypt) "yes" else "no",
        if (app.cfg.btrfs) "btrfs" else "ext4",
    }) catch {};
}

// ─────────────────────────────────────────────────────────────────────────────
// The state-machine driver. This is the readable core of the skeleton.
// ─────────────────────────────────────────────────────────────────────────────
fn step(app: *App) !void {
    // Each screen first runs its capture logic, then draws.
    switch (app.step) {
        .disk => handleDisk(app),
        .identity => handleIdentity(app),
        .edition => handleEdition(app),
        .encrypt => handleEncrypt(app),
        else => {},
    }
    draw(app);

    // Terminal-ish screens.
    if (app.step == .run) {
        // ⚠️ DESTRUCTIVE. Only reachable after the Review screen confirmed.
        if (!app.cfg.isComplete()) return error.IncompleteConfig;
        // TODO/REVIEW: gate this behind the actual Review keypress, not just flow.
        try archinstall.run(app.alloc, app.cfg);
        app.goNext(); // -> done
        return;
    }
    if (app.step == .done) {
        app.should_quit = true;
        return;
    }

    // Normal screens: react to one event.
    switch (nextAction(app)) {
        .advance => app.goNext(),
        .back => app.goBack(),
        .quit => app.should_quit = true,
        .none => {},
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // TODO: initialize libvaxis here in a real build:
    //   var tty = try vaxis.Tty.init();
    //   defer tty.deinit();
    //   var vx = try vaxis.init(alloc, .{});
    //   defer vx.deinit(alloc, tty.anyWriter());
    //   var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    //   try loop.init(); try loop.start(); defer loop.stop();
    //   try vx.enterAltScreen(tty.anyWriter());
    // (Event handling then replaces the `nextAction` stub.)
    _ = vaxis; // silence unused import in the skeleton

    var app = App{ .alloc = alloc };

    // The main loop: advance the state machine until we quit.
    // In a real build each iteration blocks on a vaxis event and redraws.
    while (!app.should_quit) {
        try step(&app);
        // SAFETY for the stub: nextAction() always "advances", so without this
        // the loop would run to .done and stop — which is the intended skeleton
        // behavior. A real event loop blocks instead and this guard is removed.
        if (app.step == .run) {
            // In the stub, do not actually exec a destructive install.
            // REVIEW: remove this short-circuit once a real Review gate exists.
            std.log.warn("SCAFFOLD: would exec archinstall here; skipping in stub", .{});
            app.should_quit = true;
        }
    }
}
