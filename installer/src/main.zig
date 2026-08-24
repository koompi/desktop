//! main.zig - KOOMPI installer TUI.
//!
//! Face over the archinstall engine. Flow: Welcome -> Locale/Timezone/Keyboard -> Disk ->
//! User/Hostname -> Edition -> Encrypt -> Review -> Run. Rendering reads
//! `installer/themes/koompi.toml` at startup and draws every screen through it — no
//! hard-coded color, glyph, or brand string below `draw()`. No vaxis: rendering is direct
//! ANSI (SGR truecolor/16-color, cursor home+clear) and input is raw termios, see
//! `loadTheme`/`draw`/`readKey`.

const std = @import("std");

const config = @import("config.zig");
const InstallConfig = config.InstallConfig;
const Edition = config.Edition;
const archinstall = @import("archinstall.zig");
const cidata = @import("cidata.zig");

// ---------------------------------------------------------------------------
// Theme: parsed from themes/koompi.toml. Schema is fixed (see that file's own
// header comment) so this is a hand-rolled parser for exactly this shape, not
// general TOML.

const Rgb = struct { r: u8, g: u8, b: u8 };

const Colors = struct {
    bg: ?Rgb = null,
    surface: ?Rgb = null,
    brand: ?Rgb = null,
    brandAlt: ?Rgb = null,
    text: ?Rgb = null,
    textDim: ?Rgb = null,
    accent: ?Rgb = null,
    success: ?Rgb = null,
    warn: ?Rgb = null,
    danger: ?Rgb = null,
    selectionBg: ?Rgb = null,
    selectionFg: ?Rgb = null,
};

const Glyphs = struct {
    tl: []const u8 = "",
    tr: []const u8 = "",
    bl: []const u8 = "",
    br: []const u8 = "",
    h: []const u8 = "",
    v: []const u8 = "",
    tee_l: []const u8 = "",
    tee_r: []const u8 = "",
    cross: []const u8 = "",
    step_done: []const u8 = "",
    step_current: []const u8 = "",
    step_upcoming: []const u8 = "",
    select: []const u8 = "",
    icon_lang: []const u8 = "",
    icon_disk: []const u8 = "",
    icon_lock: []const u8 = "",
    icon_user: []const u8 = "",
    icon_desktop: []const u8 = "",
    icon_warn: []const u8 = "",
    icon_ok: []const u8 = "",
    spinner: []const []const u8 = &.{},
    progress_full: []const u8 = "",
    progress_empty: []const u8 = "",
    check_pop: []const []const u8 = &.{},
};

const Profile = struct {
    id: []const u8 = "",
    label: []const u8 = "",
    summary: []const u8 = "",
};

const Theme = struct {
    meta_name: []const u8 = "",
    brand_ansi: []const u8 = "",
    brand_name: []const u8 = "",
    brand_edition: []const u8 = "",
    logo_path: []const u8 = "",
    logo_fallback_glyph: []const u8 = "",
    nerd_fallback: ?bool = null,
    default_locale: []const u8 = "",
    default_keymap: []const u8 = "",
    default_timezone: []const u8 = "",
    default_hostname: []const u8 = "",
    colors: Colors = .{},
    glyphs: Glyphs = .{},
    profiles: []Profile = &.{},
};

const ThemeError = error{ ThemeNotFound, MissingThemeToken, InvalidColor };

fn parseHexColor(s: []const u8) !Rgb {
    if (s.len != 7 or s[0] != '#') return ThemeError.InvalidColor;
    return .{
        .r = std.fmt.parseInt(u8, s[1..3], 16) catch return ThemeError.InvalidColor,
        .g = std.fmt.parseInt(u8, s[3..5], 16) catch return ThemeError.InvalidColor,
        .b = std.fmt.parseInt(u8, s[5..7], 16) catch return ThemeError.InvalidColor,
    };
}

fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
    return s;
}

fn parseStringArray(alloc: std.mem.Allocator, raw: []const u8) ![]const []const u8 {
    const inner_start = std.mem.indexOfScalar(u8, raw, '[') orelse return &.{};
    const inner_end = std.mem.lastIndexOfScalar(u8, raw, ']') orelse return &.{};
    const inner = raw[inner_start + 1 .. inner_end];
    var out = std.ArrayList([]const u8).init(alloc);
    var it = std.mem.splitScalar(u8, inner, ',');
    while (it.next()) |tok| {
        const trimmed = std.mem.trim(u8, tok, " \t");
        if (trimmed.len == 0) continue;
        try out.append(stripQuotes(trimmed));
    }
    return out.toOwnedSlice();
}

/// Reads `[section] key = value` pairs from `koompi.toml`'s fixed schema.
/// Values stay as slices into `raw` (arena-owned, lives for the process).
fn parseTheme(alloc: std.mem.Allocator, raw: []const u8) !Theme {
    var theme = Theme{};
    var section: []const u8 = "";
    var current_profile: ?*Profile = null;
    var profiles = std.ArrayList(Profile).init(alloc);

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.startsWith(u8, line, "[[") and std.mem.endsWith(u8, line, "]]")) {
            section = line[2 .. line.len - 2];
            try profiles.append(.{});
            current_profile = &profiles.items[profiles.items.len - 1];
            continue;
        }
        if (line[0] == '[' and std.mem.endsWith(u8, line, "]")) {
            section = line[1 .. line.len - 1];
            current_profile = null;
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");

        if (std.mem.eql(u8, section, "profiles")) {
            const p = current_profile orelse continue;
            if (std.mem.eql(u8, key, "id")) p.id = stripQuotes(value);
            if (std.mem.eql(u8, key, "label")) p.label = stripQuotes(value);
            if (std.mem.eql(u8, key, "summary")) p.summary = stripQuotes(value);
            continue;
        }
        if (std.mem.eql(u8, section, "meta")) {
            if (std.mem.eql(u8, key, "name")) theme.meta_name = stripQuotes(value);
            if (std.mem.eql(u8, key, "brand_ansi")) theme.brand_ansi = stripQuotes(value);
            continue;
        }
        if (std.mem.eql(u8, section, "brand")) {
            if (std.mem.eql(u8, key, "name")) theme.brand_name = stripQuotes(value);
            if (std.mem.eql(u8, key, "edition")) theme.brand_edition = stripQuotes(value);
            continue;
        }
        if (std.mem.eql(u8, section, "logo")) {
            if (std.mem.eql(u8, key, "path")) theme.logo_path = stripQuotes(value);
            if (std.mem.eql(u8, key, "fallback_glyph")) theme.logo_fallback_glyph = stripQuotes(value);
            continue;
        }
        if (std.mem.eql(u8, section, "font")) {
            if (std.mem.eql(u8, key, "nerd_fallback")) theme.nerd_fallback = std.mem.eql(u8, value, "true");
            continue;
        }
        if (std.mem.eql(u8, section, "defaults")) {
            if (std.mem.eql(u8, key, "locale")) theme.default_locale = stripQuotes(value);
            if (std.mem.eql(u8, key, "keymap")) theme.default_keymap = stripQuotes(value);
            if (std.mem.eql(u8, key, "timezone")) theme.default_timezone = stripQuotes(value);
            if (std.mem.eql(u8, key, "hostname")) theme.default_hostname = stripQuotes(value);
            continue;
        }
        if (std.mem.eql(u8, section, "colors")) {
            const hex = stripQuotes(value);
            inline for (.{
                .{ "bg", "bg" },       .{ "surface", "surface" },         .{ "brand", "brand" },
                .{ "brandAlt", "brandAlt" }, .{ "text", "text" },         .{ "textDim", "textDim" },
                .{ "accent", "accent" }, .{ "success", "success" },       .{ "warn", "warn" },
                .{ "danger", "danger" }, .{ "selectionBg", "selectionBg" }, .{ "selectionFg", "selectionFg" },
            }) |pair| {
                if (std.mem.eql(u8, key, pair[0])) @field(theme.colors, pair[1]) = try parseHexColor(hex);
            }
            continue;
        }
        if (std.mem.eql(u8, section, "glyphs")) {
            if (std.mem.eql(u8, key, "spinner")) {
                theme.glyphs.spinner = try parseStringArray(alloc, value);
                continue;
            }
            if (std.mem.eql(u8, key, "check_pop")) {
                theme.glyphs.check_pop = try parseStringArray(alloc, value);
                continue;
            }
            const s = stripQuotes(value);
            inline for (.{
                .{ "tl", "tl" }, .{ "tr", "tr" }, .{ "bl", "bl" }, .{ "br", "br" },
                .{ "h", "h" }, .{ "v", "v" }, .{ "tee_l", "tee_l" }, .{ "tee_r", "tee_r" },
                .{ "cross", "cross" }, .{ "step_done", "step_done" }, .{ "step_current", "step_current" },
                .{ "step_upcoming", "step_upcoming" }, .{ "select", "select" },
                .{ "icon_lang", "icon_lang" }, .{ "icon_disk", "icon_disk" }, .{ "icon_lock", "icon_lock" },
                .{ "icon_user", "icon_user" }, .{ "icon_desktop", "icon_desktop" }, .{ "icon_warn", "icon_warn" },
                .{ "icon_ok", "icon_ok" }, .{ "progress_full", "progress_full" }, .{ "progress_empty", "progress_empty" },
            }) |pair| {
                if (std.mem.eql(u8, key, pair[0])) @field(theme.glyphs, pair[1]) = s;
            }
            continue;
        }
    }

    theme.profiles = try profiles.toOwnedSlice();
    try validateTheme(theme);
    return theme;
}

/// Fails closed: a missing required token is a named error, never a silent default
/// (this is the theme file's own documented contract — see its header comment).
fn validateTheme(t: Theme) !void {
    if (t.meta_name.len == 0 or t.brand_ansi.len == 0) return ThemeError.MissingThemeToken;
    if (t.brand_name.len == 0 or t.brand_edition.len == 0) return ThemeError.MissingThemeToken;
    if (t.logo_fallback_glyph.len == 0) return ThemeError.MissingThemeToken;
    if (t.nerd_fallback == null) return ThemeError.MissingThemeToken;
    const c = t.colors;
    if (c.bg == null or c.surface == null or c.brand == null or c.brandAlt == null or
        c.text == null or c.textDim == null or c.accent == null or c.success == null or
        c.warn == null or c.danger == null or c.selectionBg == null or c.selectionFg == null)
        return ThemeError.MissingThemeToken;
    const g = t.glyphs;
    if (g.tl.len == 0 or g.tr.len == 0 or g.bl.len == 0 or g.br.len == 0 or g.h.len == 0 or
        g.v.len == 0 or g.tee_l.len == 0 or g.tee_r.len == 0 or g.cross.len == 0 or
        g.step_done.len == 0 or g.step_current.len == 0 or g.step_upcoming.len == 0 or
        g.select.len == 0 or g.progress_full.len == 0 or g.progress_empty.len == 0 or
        g.spinner.len == 0 or g.check_pop.len == 0)
        return ThemeError.MissingThemeToken;
    if (t.profiles.len == 0) return ThemeError.MissingThemeToken;
}

/// Packaged path first (nothing installs koompi.toml on a real system yet — see
/// AUDIT.md V3 — so this is forward-looking), then dev-build fallbacks: cwd-relative
/// (matches `zig build run` from `installer/`) and exe-relative (matches a copied
/// `zig-out/bin/koompi-installer` run from elsewhere).
fn loadThemeRaw(alloc: std.mem.Allocator) ![]u8 {
    if (std.fs.openFileAbsolute("/usr/share/koompi/installer/theme.toml", .{})) |f| {
        defer f.close();
        return f.readToEndAlloc(alloc, 1 << 20);
    } else |_| {}

    if (std.fs.cwd().openFile("themes/koompi.toml", .{})) |f| {
        defer f.close();
        return f.readToEndAlloc(alloc, 1 << 20);
    } else |_| {}

    const exe_dir = std.fs.selfExeDirPathAlloc(alloc) catch return ThemeError.ThemeNotFound;
    const rel = try std.fs.path.join(alloc, &.{ exe_dir, "..", "..", "themes", "koompi.toml" });
    var f = std.fs.cwd().openFile(rel, .{}) catch return ThemeError.ThemeNotFound;
    defer f.close();
    return f.readToEndAlloc(alloc, 1 << 20);
}

fn loadTheme(alloc: std.mem.Allocator) !Theme {
    const raw = try loadThemeRaw(alloc);
    return parseTheme(alloc, raw);
}

// ---------------------------------------------------------------------------
// Accessibility tiers (docs/ui-ux.md "Accessibility"): truecolor by default,
// TERM=linux/256-color degrades to 16-color + forced ASCII glyphs, NO_COLOR
// strips color entirely and renders structure + glyphs only.

const ColorTier = enum { truecolor, ansi16, none };

fn detectColorTier() ColorTier {
    if (std.posix.getenv("NO_COLOR")) |_| return .none;
    const term = std.posix.getenv("TERM") orelse return .ansi16;
    if (std.mem.eql(u8, term, "linux")) return .ansi16; // console framebuffer: never truecolor
    if (std.posix.getenv("COLORTERM")) |ct| {
        if (std.mem.indexOf(u8, ct, "truecolor") != null or std.mem.indexOf(u8, ct, "24bit") != null) return .truecolor;
    }
    if (std.mem.indexOf(u8, term, "256color") != null) return .ansi16;
    return .truecolor;
}

const ColorToken = enum { bg, surface, brand, brandAlt, text, textDim, accent, success, warn, danger, selectionBg, selectionFg };

fn rgbOf(t: *const Theme, tok: ColorToken) Rgb {
    return switch (tok) {
        .bg => t.colors.bg.?,
        .surface => t.colors.surface.?,
        .brand => t.colors.brand.?,
        .brandAlt => t.colors.brandAlt.?,
        .text => t.colors.text.?,
        .textDim => t.colors.textDim.?,
        .accent => t.colors.accent.?,
        .success => t.colors.success.?,
        .warn => t.colors.warn.?,
        .danger => t.colors.danger.?,
        .selectionBg => t.colors.selectionBg.?,
        .selectionFg => t.colors.selectionFg.?,
    };
}

// Nearest-16-color mapping per docs/ui-ux.md Accessibility tier 2.
fn ansi16Of(tok: ColorToken) struct { code: u8, bright: bool } {
    return switch (tok) {
        .bg, .surface => .{ .code = 0, .bright = false },
        .brand, .selectionBg => .{ .code = 4, .bright = true },
        .brandAlt => .{ .code = 4, .bright = false },
        .text => .{ .code = 7, .bright = true },
        .textDim => .{ .code = 0, .bright = true },
        .accent => .{ .code = 6, .bright = true },
        .success => .{ .code = 2, .bright = false },
        .warn => .{ .code = 3, .bright = false },
        .danger => .{ .code = 1, .bright = true },
        .selectionFg => .{ .code = 0, .bright = false },
    };
}

fn fg(w: anytype, t: *const Theme, tier: ColorTier, tok: ColorToken) !void {
    switch (tier) {
        .none => {},
        .truecolor => {
            const c = rgbOf(t, tok);
            try w.print("\x1b[38;2;{d};{d};{d}m", .{ c.r, c.g, c.b });
        },
        .ansi16 => {
            const a = ansi16Of(tok);
            try w.print("\x1b[{d}m", .{@as(u16, if (a.bright) 90 else 30) + a.code});
        },
    }
}

fn bg(w: anytype, t: *const Theme, tier: ColorTier, tok: ColorToken) !void {
    switch (tier) {
        .none => {},
        .truecolor => {
            const c = rgbOf(t, tok);
            try w.print("\x1b[48;2;{d};{d};{d}m", .{ c.r, c.g, c.b });
        },
        .ansi16 => {
            const a = ansi16Of(tok);
            try w.print("\x1b[{d}m", .{@as(u16, if (a.bright) 100 else 40) + a.code});
        },
    }
}

fn resetSGR(w: anytype, tier: ColorTier) !void {
    if (tier != .none) try w.writeAll("\x1b[0m");
}

// ---------------------------------------------------------------------------
// Nerd-Font icon column vs its ASCII fallback (docs/ui-ux.md Typography table).
// The ASCII column is fixed by that table, not themed — only the Nerd column
// comes from koompi.toml.

const IconPurpose = enum { lang, disk, lock, user, desktop, warn, ok };

fn icon(t: *const Theme, ascii_forced: bool, purpose: IconPurpose) []const u8 {
    if (ascii_forced) return switch (purpose) {
        .lang => "@",
        .disk => "#",
        .lock => "*",
        .user => "&",
        .desktop => "%",
        .warn => "!",
        .ok => "+",
    };
    return switch (purpose) {
        .lang => t.glyphs.icon_lang,
        .disk => t.glyphs.icon_disk,
        .lock => t.glyphs.icon_lock,
        .user => t.glyphs.icon_user,
        .desktop => t.glyphs.icon_desktop,
        .warn => t.glyphs.icon_warn,
        .ok => t.glyphs.icon_ok,
    };
}

fn stepGlyph(t: *const Theme, ascii_forced: bool, comptime which: enum { done, current, upcoming }) []const u8 {
    if (ascii_forced) return switch (which) {
        .done => "x",
        .current => ">",
        .upcoming => "-",
    };
    return switch (which) {
        .done => t.glyphs.step_done,
        .current => t.glyphs.step_current,
        .upcoming => t.glyphs.step_upcoming,
    };
}

fn selectGlyph(t: *const Theme, ascii_forced: bool) []const u8 {
    return if (ascii_forced) ">" else t.glyphs.select;
}

// ---------------------------------------------------------------------------
// The installer's linear-but-back-navigable steps. The state machine is just
// "which screen are we on"; each screen mutates one slice of InstallConfig.
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

const all_steps = [_]Step{ .welcome, .locale, .disk, .identity, .edition, .encrypt, .review, .run, .done };

/// Whole-app state: where we are + everything we've collected so far.
const App = struct {
    alloc: std.mem.Allocator,
    step: Step = .welcome,
    cfg: InstallConfig = .{},
    should_quit: bool = false,

    fn goNext(self: *App) void {
        self.step = self.step.next();
    }
    fn goBack(self: *App) void {
        self.step = self.step.prev();
    }
};

// Event model.
const Action = enum { advance, back, quit, none };

/// Raw termios on stdin, restored on `deinit`. Fails open: if stdin isn't a
/// real tty (piped/non-interactive), `enable()` returns null and callers fall
/// back to the auto-advance stub behavior — same fail-open convention as
/// `cidata.detect`.
const RawMode = struct {
    orig: std.posix.termios,

    fn enable() ?RawMode {
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

    fn disable(self: RawMode) void {
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

fn nextAction(raw: ?RawMode) Action {
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

fn handleDisk(app: *App) void {
    const disks = enumerateDisks(app.alloc);
    // TODO: let the user pick from `disks`; capture selection. Skeleton takes [0].
    if (disks.len != 0) app.cfg.disk_path = disks[0];
}

fn handleIdentity(app: *App) void {
    // TODO: text fields for hostname / username / password.
    // SECURITY: the password field must be masked, and the captured secret
    // should go straight toward archinstall.writeUserCredentials - see the note
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

// ---------------------------------------------------------------------------
// Rendering. Chrome (header/rail/footer) per docs/ui-ux.md "Persistent chrome":
// 80x24 budget, clamped to 72 columns of drawn width, rail = 20 cols incl. its
// divider, content = the remainder.

const TOTAL_WIDTH = 72;
const RAIL_LABEL_WIDTH = 19;
const CONTENT_WIDTH = TOTAL_WIDTH - 1 - RAIL_LABEL_WIDTH - 1 - 1;

fn codepointLen(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

fn writeCell(w: anytype, text: []const u8, width: usize) !void {
    try w.writeAll(text);
    const len = codepointLen(text);
    var i: usize = len;
    while (i < width) : (i += 1) try w.writeAll(" ");
}

fn writeHRun(w: anytype, glyph: []const u8, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) try w.writeAll(glyph);
}

const Ctx = struct {
    theme: *const Theme,
    tier: ColorTier,
    ascii_forced: bool,
};

fn drawTopBorder(w: anytype, ctx: Ctx) !void {
    try fg(w, ctx.theme, ctx.tier, .brandAlt);
    try w.writeAll(ctx.theme.glyphs.tl);
    try writeHRun(w, ctx.theme.glyphs.h, TOTAL_WIDTH - 2);
    try w.writeAll(ctx.theme.glyphs.tr);
    try resetSGR(w, ctx.tier);
    try w.writeAll("\n");
}

fn drawBottomBorder(w: anytype, ctx: Ctx) !void {
    try fg(w, ctx.theme, ctx.tier, .brandAlt);
    try w.writeAll(ctx.theme.glyphs.bl);
    try writeHRun(w, ctx.theme.glyphs.h, TOTAL_WIDTH - 2);
    try w.writeAll(ctx.theme.glyphs.br);
    try resetSGR(w, ctx.tier);
    try w.writeAll("\n");
}

fn drawDivider(w: anytype, ctx: Ctx) !void {
    try fg(w, ctx.theme, ctx.tier, .brandAlt);
    try w.writeAll(ctx.theme.glyphs.tee_l);
    try writeHRun(w, ctx.theme.glyphs.h, RAIL_LABEL_WIDTH);
    try w.writeAll(ctx.theme.glyphs.cross);
    try writeHRun(w, ctx.theme.glyphs.h, CONTENT_WIDTH);
    try w.writeAll(ctx.theme.glyphs.tee_r);
    try resetSGR(w, ctx.tier);
    try w.writeAll("\n");
}

fn drawHeader(w: anytype, ctx: Ctx, screen: Step) !void {
    try drawTopBorder(w, ctx);

    var buf: [TOTAL_WIDTH * 4]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const bw = fbs.writer();
    try bw.print(" {s} {s} · {s}", .{ ctx.theme.logo_fallback_glyph, ctx.theme.brand_name, ctx.theme.brand_edition });
    const left = fbs.getWritten();

    var buf2: [TOTAL_WIDTH * 4]u8 = undefined;
    var fbs2 = std.io.fixedBufferStream(&buf2);
    try fbs2.writer().print("{s} ", .{screen.title()});
    const right = fbs2.getWritten();

    try fg(w, ctx.theme, ctx.tier, .brandAlt);
    try w.writeAll(ctx.theme.glyphs.v);
    try resetSGR(w, ctx.tier);
    try fg(w, ctx.theme, ctx.tier, .brand);
    try w.writeAll(left);
    const used = codepointLen(left) + codepointLen(right);
    var pad = used;
    while (pad < TOTAL_WIDTH - 2) : (pad += 1) try w.writeAll(" ");
    try fg(w, ctx.theme, ctx.tier, .textDim);
    try w.writeAll(right);
    try resetSGR(w, ctx.tier);
    try fg(w, ctx.theme, ctx.tier, .brandAlt);
    try w.writeAll(ctx.theme.glyphs.v);
    try resetSGR(w, ctx.tier);
    try w.writeAll("\n");

    try drawDivider(w, ctx);
}

fn drawFooter(w: anytype, ctx: Ctx, hint: []const u8) !void {
    try drawDivider(w, ctx);
    try fg(w, ctx.theme, ctx.tier, .brandAlt);
    try w.writeAll(ctx.theme.glyphs.v);
    try resetSGR(w, ctx.tier);
    try fg(w, ctx.theme, ctx.tier, .textDim);
    try writeCell(w, hint, TOTAL_WIDTH - 2);
    try resetSGR(w, ctx.tier);
    try fg(w, ctx.theme, ctx.tier, .brandAlt);
    try w.writeAll(ctx.theme.glyphs.v);
    try resetSGR(w, ctx.tier);
    try w.writeAll("\n");
    try drawBottomBorder(w, ctx);
}

fn railLine(ctx: Ctx, current: Step, s: Step, buf: []u8) []const u8 {
    const glyph = if (s == current)
        stepGlyph(ctx.theme, ctx.ascii_forced, .current)
    else if (@intFromEnum(s) < @intFromEnum(current))
        stepGlyph(ctx.theme, ctx.ascii_forced, .done)
    else
        stepGlyph(ctx.theme, ctx.ascii_forced, .upcoming);
    return std.fmt.bufPrint(buf, " {s} {s}", .{ glyph, s.title() }) catch buf;
}

fn drawRailAndContent(w: anytype, ctx: Ctx, screen: Step, content_lines: []const []const u8) !void {
    const row_count = @max(all_steps.len, content_lines.len);
    var row: usize = 0;
    while (row < row_count) : (row += 1) {
        try fg(w, ctx.theme, ctx.tier, .brandAlt);
        try w.writeAll(ctx.theme.glyphs.v);
        try resetSGR(w, ctx.tier);

        if (row < all_steps.len) {
            const s = all_steps[row];
            var buf: [64]u8 = undefined;
            const text = railLine(ctx, screen, s, &buf);
            if (s == screen) {
                try fg(w, ctx.theme, ctx.tier, .brand);
            } else if (@intFromEnum(s) < @intFromEnum(screen)) {
                try fg(w, ctx.theme, ctx.tier, .success);
            } else {
                try fg(w, ctx.theme, ctx.tier, .textDim);
            }
            try writeCell(w, text, RAIL_LABEL_WIDTH);
            try resetSGR(w, ctx.tier);
        } else {
            try writeCell(w, "", RAIL_LABEL_WIDTH);
        }

        try fg(w, ctx.theme, ctx.tier, .brandAlt);
        try w.writeAll(ctx.theme.glyphs.v);
        try resetSGR(w, ctx.tier);

        const line = if (row < content_lines.len) content_lines[row] else "";
        try fg(w, ctx.theme, ctx.tier, .text);
        try writeCell(w, line, CONTENT_WIDTH);
        try resetSGR(w, ctx.tier);

        try fg(w, ctx.theme, ctx.tier, .brandAlt);
        try w.writeAll(ctx.theme.glyphs.v);
        try resetSGR(w, ctx.tier);
        try w.writeAll("\n");
    }
}

fn footerFor(screen: Step, ascii_forced: bool) []const u8 {
    if (screen == .review) {
        return if (ascii_forced) "Enter: INSTALL (destructive)  Esc: back  ^C: quit" else "⏎ INSTALL (destructive)   Esc back   ^C quit";
    }
    if (screen == .welcome) {
        return if (ascii_forced) "Enter: continue  ^C: quit" else "⏎ continue   ^C quit";
    }
    if (screen == .done or screen == .run) {
        return "^C quit";
    }
    return if (ascii_forced) "Enter: next  Esc: back  ^C: quit" else "⏎ next   Esc back   ^C quit";
}

fn contentLines(app: *App, ctx: Ctx, alloc: std.mem.Allocator) ![]const []const u8 {
    var lines = std.ArrayList([]const u8).init(alloc);
    const cfg = app.cfg;

    switch (app.step) {
        .welcome => {
            try lines.append(try std.fmt.allocPrint(alloc, "{s} {s} — {s}", .{ ctx.theme.logo_fallback_glyph, ctx.theme.brand_name, ctx.theme.brand_edition }));
            try lines.append("");
            try lines.append("This installer will set up your machine.");
        },
        .locale => {
            try lines.append(try std.fmt.allocPrint(alloc, "{s} locale    {s}", .{ icon(ctx.theme, ctx.ascii_forced, .lang), cfg.locale }));
            try lines.append(try std.fmt.allocPrint(alloc, "  timezone  {s}", .{cfg.timezone}));
            try lines.append(try std.fmt.allocPrint(alloc, "  keymap    {s}", .{cfg.keymap}));
        },
        .disk => {
            const shown = if (cfg.disk_path.len != 0) cfg.disk_path else "<none>";
            try lines.append(try std.fmt.allocPrint(alloc, "{s} target disk", .{icon(ctx.theme, ctx.ascii_forced, .disk)}));
            try lines.append(try std.fmt.allocPrint(alloc, "{s} {s}", .{ selectGlyph(ctx.theme, ctx.ascii_forced), shown }));
        },
        .identity => {
            try lines.append(try std.fmt.allocPrint(alloc, "{s} hostname  {s}", .{ icon(ctx.theme, ctx.ascii_forced, .user), cfg.hostname }));
            try lines.append(try std.fmt.allocPrint(alloc, "  username  {s}", .{cfg.username}));
            try lines.append("  password  <hidden>");
        },
        .edition => {
            for (ctx.theme.profiles) |p| {
                const marker = if (std.mem.eql(u8, p.id, archinstall.targetPackage(cfg.edition))) selectGlyph(ctx.theme, ctx.ascii_forced) else " ";
                try lines.append(try std.fmt.allocPrint(alloc, "{s} {s} {s}  {s}", .{ marker, icon(ctx.theme, ctx.ascii_forced, .desktop), p.label, p.summary }));
            }
        },
        .encrypt => {
            const state = if (cfg.encrypt) "ON" else "OFF";
            try lines.append(try std.fmt.allocPrint(alloc, "{s} encryption (LUKS)  {s}", .{ icon(ctx.theme, ctx.ascii_forced, .lock), state }));
        },
        .review => {
            const pkg = archinstall.targetPackage(cfg.edition);
            try lines.append(try std.fmt.allocPrint(alloc, "edition   {s}  ({s})", .{ cfg.edition.label(), pkg }));
            try lines.append(try std.fmt.allocPrint(alloc, "{s} disk    {s}  WILL BE ERASED", .{ icon(ctx.theme, ctx.ascii_forced, .warn), cfg.disk_path }));
            try lines.append(try std.fmt.allocPrint(alloc, "hostname  {s}", .{cfg.hostname}));
            try lines.append(try std.fmt.allocPrint(alloc, "user      {s}", .{cfg.username}));
            try lines.append(try std.fmt.allocPrint(alloc, "locale    {s}  tz {s}  keymap {s}", .{ cfg.locale, cfg.timezone, cfg.keymap }));
            try lines.append(try std.fmt.allocPrint(alloc, "encrypt   {s}  fs {s}", .{ if (cfg.encrypt) "yes" else "no", if (cfg.btrfs) "btrfs" else "ext4" }));
        },
        .run => {
            const spinner_frame = if (ctx.tier == .truecolor) ctx.theme.glyphs.spinner[0] else "*";
            try lines.append(try std.fmt.allocPrint(alloc, "{s} Running archinstall + post-install hook…", .{spinner_frame}));
            var bar: [40]u8 = undefined;
            var i: usize = 0;
            var bw = std.io.fixedBufferStream(&bar);
            while (i < 6) : (i += 1) _ = bw.writer().write(ctx.theme.glyphs.progress_full) catch {};
            while (i < 20) : (i += 1) _ = bw.writer().write(ctx.theme.glyphs.progress_empty) catch {};
            try lines.append(try std.fmt.allocPrint(alloc, "{s}", .{bw.getWritten()}));
        },
        .done => {
            try lines.append(try std.fmt.allocPrint(alloc, "{s} Installation complete.", .{icon(ctx.theme, ctx.ascii_forced, .ok)}));
            try lines.append("Reboot into KOOMPI OS.");
        },
    }
    return lines.toOwnedSlice();
}

fn draw(app: *App, ctx: Ctx) void {
    const out = std.io.getStdOut().writer();
    out.writeAll("\x1b[2J\x1b[H") catch {};

    var arena = std.heap.ArenaAllocator.init(app.alloc);
    defer arena.deinit();

    drawHeader(out, ctx, app.step) catch {};
    const lines = contentLines(app, ctx, arena.allocator()) catch &.{};
    drawRailAndContent(out, ctx, app.step, lines) catch {};
    drawFooter(out, ctx, footerFor(app.step, ctx.ascii_forced)) catch {};

    if (app.step == .review and !app.cfg.isComplete()) {
        fg(out, ctx.theme, ctx.tier, .danger) catch {};
        out.print("{s} incomplete: fill in the required fields before installing.\n", .{icon(ctx.theme, ctx.ascii_forced, .warn)}) catch {};
        resetSGR(out, ctx.tier) catch {};
    }
}

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

test "parseHexColor parses valid and rejects invalid" {
    const c = try parseHexColor("#1793D1");
    try std.testing.expectEqual(@as(u8, 0x17), c.r);
    try std.testing.expectEqual(@as(u8, 0x93), c.g);
    try std.testing.expectEqual(@as(u8, 0xD1), c.b);
    try std.testing.expectError(ThemeError.InvalidColor, parseHexColor("1793D1"));
    try std.testing.expectError(ThemeError.InvalidColor, parseHexColor("#1793D"));
}

test "parseTheme loads the shipped koompi.toml" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const raw = try loadThemeRaw(arena.allocator());
    const theme = try parseTheme(arena.allocator(), raw);
    try std.testing.expectEqualStrings("KOOMPI OS", theme.brand_name);
    try std.testing.expectEqualStrings("Naga", theme.brand_edition);
    try std.testing.expectEqual(@as(u8, 0x17), theme.colors.brand.?.r);
    try std.testing.expect(theme.nerd_fallback.?);
    try std.testing.expectEqual(@as(usize, 2), theme.profiles.len);
    try std.testing.expectEqualStrings("koompi-desktop-hyprland", theme.profiles[0].id);
    try std.testing.expectEqual(@as(usize, 10), theme.glyphs.spinner.len);
}

test "ascii fallback table used only when forced" {
    var theme = Theme{};
    theme.glyphs.icon_disk = "";
    try std.testing.expectEqualStrings("#", icon(&theme, true, .disk));
    try std.testing.expectEqualStrings("", icon(&theme, false, .disk));
    try std.testing.expectEqualStrings("x", stepGlyph(&theme, true, .done));
    try std.testing.expectEqualStrings(">", selectGlyph(&theme, true));
}

test "validateTheme fails closed on a missing token" {
    var theme = Theme{};
    theme.brand_name = "x";
    try std.testing.expectError(ThemeError.MissingThemeToken, validateTheme(theme));
}
