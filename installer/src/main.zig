//! main.zig - KOOMPI installer TUI.
//!
//! Face over the archinstall engine. Flow: Welcome -> Locale/Timezone/Keyboard -> Disk ->
//! User/Hostname -> Edition -> Encrypt -> Review -> Run. Rendering reads
//! `installer/themes/koompi.toml` at startup and draws every screen through it — no
//! hard-coded color, glyph, or brand string below `ui.draw()`. No vaxis: rendering is direct
//! ANSI (SGR truecolor/16-color, cursor home+clear) and input is raw termios.
//! theme.zig parses the theme, term.zig picks the color tier and glyphs, app.zig holds the
//! state machine + input + handlers, ui.zig renders a frame; this file is the driver.

const std = @import("std");

const archinstall = @import("archinstall.zig");
const cidata = @import("cidata.zig");
const loadTheme = @import("theme.zig").loadTheme;
const detectColorTier = @import("term.zig").detectColorTier;
const app_mod = @import("app.zig");
const App = app_mod.App;
const RawMode = app_mod.RawMode;
const nextAction = app_mod.nextAction;
const handleDisk = app_mod.handleDisk;
const handleIdentity = app_mod.handleIdentity;
const handleEdition = app_mod.handleEdition;
const handleEncrypt = app_mod.handleEncrypt;
const ui = @import("ui.zig");
const Ctx = ui.Ctx;
const draw = ui.draw;

// The state-machine driver. This is the readable core of the skeleton.
fn step(app: *App, ctx: Ctx, raw: ?RawMode) !void {
    // Each screen first runs its capture logic, then draws.
    switch (app.step) {
        .disk => handleDisk(app),
        .identity => handleIdentity(app),
        .edition => handleEdition(app),
        .encrypt => handleEncrypt(app),
        else => {},
    }
    draw(app, ctx);

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
    switch (nextAction(raw)) {
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

    var theme_arena = std.heap.ArenaAllocator.init(alloc);
    defer theme_arena.deinit();
    const theme = try loadTheme(theme_arena.allocator());

    const tier = detectColorTier();
    const ascii_forced = !theme.nerd_fallback.? or tier == .ansi16;
    const ctx = Ctx{ .theme = &theme, .tier = tier, .ascii_forced = ascii_forced };

    var app = App{ .alloc = alloc };

    // Unattended install: a cidata-labeled seed drive skips (or defers) the wizard.
    // Must fail open - .none leaves app.step at its .welcome default.
    switch (try cidata.detect(alloc, &app.cfg)) {
        .none => {},
        .configured, .deferred => {
            // No interactive Review screen is reached on this path; render its
            // summary anyway so an unattended wipe still has an audit trail.
            app.step = .review;
            draw(&app, ctx);
            app.step = .run;
        },
    }

    const raw = RawMode.enable();
    defer if (raw) |r| r.disable();

    // The main loop: advance the state machine until we quit.
    while (!app.should_quit) {
        try step(&app, ctx, raw);
        if (app.step == .run) {
            // In the stub, do not actually exec a destructive install.
            // REVIEW: remove this short-circuit once a real Review gate exists.
            std.log.warn("SCAFFOLD: would exec archinstall here; skipping in stub", .{});
            app.should_quit = true;
        }
    }
}

test {
    _ = @import("theme.zig");
    _ = @import("term.zig");
    _ = @import("app.zig");
    _ = @import("ui.zig");
}
