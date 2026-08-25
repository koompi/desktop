//! ui.zig - frame rendering.
//!
//! Chrome (header/rail/footer) per docs/ui-ux.md "Persistent chrome":
//! 80x24 budget, clamped to 72 columns of drawn width, rail = 20 cols incl. its
//! divider, content = the remainder.

const std = @import("std");

const archinstall = @import("archinstall.zig");
const theme_mod = @import("theme.zig");
const Theme = theme_mod.Theme;
const term = @import("term.zig");
const ColorTier = term.ColorTier;
const fg = term.fg;
const resetSGR = term.resetSGR;
const icon = term.icon;
const stepGlyph = term.stepGlyph;
const selectGlyph = term.selectGlyph;
const app_mod = @import("app.zig");
const Step = app_mod.Step;
const all_steps = app_mod.all_steps;
const App = app_mod.App;

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

pub const Ctx = struct {
    io: std.Io,
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
    var bw = std.Io.Writer.fixed(&buf);
    try bw.print(" {s} {s} · {s}", .{ ctx.theme.logo_fallback_glyph, ctx.theme.brand_name, ctx.theme.brand_edition });
    const left = bw.buffered();

    var buf2: [TOTAL_WIDTH * 4]u8 = undefined;
    var bw2 = std.Io.Writer.fixed(&buf2);
    try bw2.print("{s} ", .{screen.title()});
    const right = bw2.buffered();

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
    var lines: std.ArrayList([]const u8) = .empty;
    const cfg = app.cfg;

    switch (app.step) {
        .welcome => {
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} {s} — {s}", .{ ctx.theme.logo_fallback_glyph, ctx.theme.brand_name, ctx.theme.brand_edition }));
            try lines.append(alloc, "");
            try lines.append(alloc, "This installer will set up your machine.");
        },
        .locale => {
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} locale    {s}", .{ icon(ctx.theme, ctx.ascii_forced, .lang), cfg.locale }));
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "  timezone  {s}", .{cfg.timezone}));
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "  keymap    {s}", .{cfg.keymap}));
        },
        .disk => {
            const shown = if (cfg.disk_path.len != 0) cfg.disk_path else "<none>";
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} target disk", .{icon(ctx.theme, ctx.ascii_forced, .disk)}));
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} {s}", .{ selectGlyph(ctx.theme, ctx.ascii_forced), shown }));
        },
        .identity => {
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} hostname  {s}", .{ icon(ctx.theme, ctx.ascii_forced, .user), cfg.hostname }));
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "  username  {s}", .{cfg.username}));
            try lines.append(alloc, "  password  <hidden>");
        },
        .edition => {
            for (ctx.theme.profiles) |p| {
                const marker = if (std.mem.eql(u8, p.id, archinstall.targetPackage(cfg.edition))) selectGlyph(ctx.theme, ctx.ascii_forced) else " ";
                try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} {s} {s}  {s}", .{ marker, icon(ctx.theme, ctx.ascii_forced, .desktop), p.label, p.summary }));
            }
        },
        .encrypt => {
            const state = if (cfg.encrypt) "ON" else "OFF";
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} encryption (LUKS)  {s}", .{ icon(ctx.theme, ctx.ascii_forced, .lock), state }));
        },
        .review => {
            const pkg = archinstall.targetPackage(cfg.edition);
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "edition   {s}  ({s})", .{ cfg.edition.label(), pkg }));
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} disk    {s}  WILL BE ERASED", .{ icon(ctx.theme, ctx.ascii_forced, .warn), cfg.disk_path }));
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "hostname  {s}", .{cfg.hostname}));
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "user      {s}", .{cfg.username}));
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "locale    {s}  tz {s}  keymap {s}", .{ cfg.locale, cfg.timezone, cfg.keymap }));
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "encrypt   {s}  fs {s}", .{ if (cfg.encrypt) "yes" else "no", if (cfg.btrfs) "btrfs" else "ext4" }));
        },
        .run => {
            const spinner_frame = if (ctx.tier == .truecolor) ctx.theme.glyphs.spinner[0] else "*";
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} Running archinstall + post-install hook…", .{spinner_frame}));
            var bar: [40]u8 = undefined;
            var i: usize = 0;
            var bw = std.Io.Writer.fixed(&bar);
            while (i < 6) : (i += 1) _ = bw.write(ctx.theme.glyphs.progress_full) catch {};
            while (i < 20) : (i += 1) _ = bw.write(ctx.theme.glyphs.progress_empty) catch {};
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s}", .{bw.buffered()}));
        },
        .done => {
            try lines.append(alloc, try std.fmt.allocPrint(alloc, "{s} Installation complete.", .{icon(ctx.theme, ctx.ascii_forced, .ok)}));
            try lines.append(alloc, "Reboot into KOOMPI OS.");
        },
    }
    return lines.toOwnedSlice(alloc);
}

pub fn draw(app: *App, ctx: Ctx) void {
    var out_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(ctx.io, &out_buf);
    const out = &stdout.interface;
    defer out.flush() catch {};
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
