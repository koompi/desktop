//! term.zig - terminal output tiers and glyph selection.
//!
//! Accessibility tiers (docs/ui-ux.md "Accessibility"): truecolor by default,
//! TERM=linux/256-color degrades to 16-color + forced ASCII glyphs, NO_COLOR
//! strips color entirely and renders structure + glyphs only.
//!
//! Nerd-Font icon column vs its ASCII fallback (docs/ui-ux.md Typography table).
//! The ASCII column is fixed by that table, not themed — only the Nerd column
//! comes from koompi.toml.

const std = @import("std");

const theme_mod = @import("theme.zig");
const Theme = theme_mod.Theme;
const Rgb = theme_mod.Rgb;

pub const ColorTier = enum { truecolor, ansi16, none };

pub fn detectColorTier(environ: std.process.Environ) ColorTier {
    if (environ.getPosix("NO_COLOR")) |_| return .none;
    const term = environ.getPosix("TERM") orelse return .ansi16;
    if (std.mem.eql(u8, term, "linux")) return .ansi16; // console framebuffer: never truecolor
    if (environ.getPosix("COLORTERM")) |ct| {
        if (std.mem.indexOf(u8, ct, "truecolor") != null or std.mem.indexOf(u8, ct, "24bit") != null) return .truecolor;
    }
    if (std.mem.indexOf(u8, term, "256color") != null) return .ansi16;
    return .truecolor;
}

pub const ColorToken = enum { bg, surface, brand, brandAlt, text, textDim, accent, success, warn, danger, selectionBg, selectionFg };

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

pub fn fg(w: anytype, t: *const Theme, tier: ColorTier, tok: ColorToken) !void {
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

pub fn bg(w: anytype, t: *const Theme, tier: ColorTier, tok: ColorToken) !void {
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

pub fn resetSGR(w: anytype, tier: ColorTier) !void {
    if (tier != .none) try w.writeAll("\x1b[0m");
}

pub const IconPurpose = enum { lang, disk, lock, user, desktop, warn, ok };

pub fn icon(t: *const Theme, ascii_forced: bool, purpose: IconPurpose) []const u8 {
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

pub fn stepGlyph(t: *const Theme, ascii_forced: bool, comptime which: enum { done, current, upcoming }) []const u8 {
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

pub fn selectGlyph(t: *const Theme, ascii_forced: bool) []const u8 {
    return if (ascii_forced) ">" else t.glyphs.select;
}

test "ascii fallback table used only when forced" {
    var theme = Theme{};
    theme.glyphs.icon_disk = "";
    try std.testing.expectEqualStrings("#", icon(&theme, true, .disk));
    try std.testing.expectEqualStrings("", icon(&theme, false, .disk));
    try std.testing.expectEqualStrings("x", stepGlyph(&theme, true, .done));
    try std.testing.expectEqualStrings(">", selectGlyph(&theme, true));
}
