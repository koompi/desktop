//! theme.zig - the installer theme, parsed from themes/koompi.toml.
//!
//! Schema is fixed (see that file's own header comment) so this is a hand-rolled
//! parser for exactly this shape, not general TOML.

const std = @import("std");

pub const Rgb = struct { r: u8, g: u8, b: u8 };

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

pub const Glyphs = struct {
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

pub const Profile = struct {
    id: []const u8 = "",
    label: []const u8 = "",
    summary: []const u8 = "",
};

pub const Theme = struct {
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

pub const ThemeError = error{ ThemeNotFound, MissingThemeToken, InvalidColor };

pub fn parseHexColor(s: []const u8) !Rgb {
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
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, inner, ',');
    while (it.next()) |tok| {
        const trimmed = std.mem.trim(u8, tok, " \t");
        if (trimmed.len == 0) continue;
        try out.append(alloc, stripQuotes(trimmed));
    }
    return out.toOwnedSlice(alloc);
}

/// Reads `[section] key = value` pairs from `koompi.toml`'s fixed schema.
/// Values stay as slices into `raw` (arena-owned, lives for the process).
pub fn parseTheme(alloc: std.mem.Allocator, raw: []const u8) !Theme {
    var theme = Theme{};
    var section: []const u8 = "";
    var current_profile: ?*Profile = null;
    var profiles: std.ArrayList(Profile) = .empty;

    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.startsWith(u8, line, "[[") and std.mem.endsWith(u8, line, "]]")) {
            section = line[2 .. line.len - 2];
            try profiles.append(alloc, .{});
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
                .{ "bg", "bg" },             .{ "surface", "surface" },         .{ "brand", "brand" },
                .{ "brandAlt", "brandAlt" }, .{ "text", "text" },               .{ "textDim", "textDim" },
                .{ "accent", "accent" },     .{ "success", "success" },         .{ "warn", "warn" },
                .{ "danger", "danger" },     .{ "selectionBg", "selectionBg" }, .{ "selectionFg", "selectionFg" },
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
                .{ "tl", "tl" },                       .{ "tr", "tr" },                         .{ "bl", "bl" },                     .{ "br", "br" },
                .{ "h", "h" },                         .{ "v", "v" },                           .{ "tee_l", "tee_l" },               .{ "tee_r", "tee_r" },
                .{ "cross", "cross" },                 .{ "step_done", "step_done" },           .{ "step_current", "step_current" }, .{ "step_upcoming", "step_upcoming" },
                .{ "select", "select" },               .{ "icon_lang", "icon_lang" },           .{ "icon_disk", "icon_disk" },       .{ "icon_lock", "icon_lock" },
                .{ "icon_user", "icon_user" },         .{ "icon_desktop", "icon_desktop" },     .{ "icon_warn", "icon_warn" },       .{ "icon_ok", "icon_ok" },
                .{ "progress_full", "progress_full" }, .{ "progress_empty", "progress_empty" },
            }) |pair| {
                if (std.mem.eql(u8, key, pair[0])) @field(theme.glyphs, pair[1]) = s;
            }
            continue;
        }
    }

    theme.profiles = try profiles.toOwnedSlice(alloc);
    try validateTheme(theme);
    return theme;
}

/// Fails closed: a missing required token is a named error, never a silent default
/// (this is the theme file's own documented contract — see its header comment).
pub fn validateTheme(t: Theme) !void {
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
pub fn loadThemeRaw(io: std.Io, alloc: std.mem.Allocator) ![]u8 {
    const cwd = std.Io.Dir.cwd();
    const limit: std.Io.Limit = .limited(1 << 20);
    if (cwd.readFileAlloc(io, "/usr/share/koompi/installer/theme.toml", alloc, limit)) |raw| return raw else |_| {}
    if (cwd.readFileAlloc(io, "themes/koompi.toml", alloc, limit)) |raw| return raw else |_| {}

    const exe_dir = std.process.executableDirPathAlloc(io, alloc) catch return ThemeError.ThemeNotFound;
    const rel = try std.fs.path.join(alloc, &.{ exe_dir, "..", "..", "themes", "koompi.toml" });
    return cwd.readFileAlloc(io, rel, alloc, limit) catch return ThemeError.ThemeNotFound;
}

pub fn loadTheme(io: std.Io, alloc: std.mem.Allocator) !Theme {
    const raw = try loadThemeRaw(io, alloc);
    return parseTheme(alloc, raw);
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
    const raw = try loadThemeRaw(std.testing.io, arena.allocator());
    const theme = try parseTheme(arena.allocator(), raw);
    try std.testing.expectEqualStrings("KOOMPI OS", theme.brand_name);
    try std.testing.expectEqualStrings("Naga", theme.brand_edition);
    try std.testing.expectEqual(@as(u8, 0x17), theme.colors.brand.?.r);
    try std.testing.expect(theme.nerd_fallback.?);
    try std.testing.expectEqual(@as(usize, 2), theme.profiles.len);
    try std.testing.expectEqualStrings("koompi-desktop-hyprland", theme.profiles[0].id);
    try std.testing.expectEqual(@as(usize, 10), theme.glyphs.spinner.len);
}

test "validateTheme fails closed on a missing token" {
    var theme = Theme{};
    theme.brand_name = "x";
    try std.testing.expectError(ThemeError.MissingThemeToken, validateTheme(theme));
}
