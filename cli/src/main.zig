const std = @import("std");

const version = "0.1.0";

const Command = struct {
    name: []const u8,
    helper: []const u8,
    usage: []const u8,
    summary: []const u8,
};

const commands = [_]Command{
    .{ .name = "update", .helper = "@update", .usage = "koompi update [--dry-run] [--yes] [--no-reload]", .summary = "Update packages or the installed checkout" },
    .{ .name = "doctor", .helper = "koompi-health", .usage = "koompi doctor", .summary = "Check the desktop session and its services" },
    .{ .name = "health", .helper = "koompi-health", .usage = "koompi health", .summary = "Alias for doctor" },
    .{ .name = "settings", .helper = "koompi-settings", .usage = "koompi settings [page]", .summary = "Open KOOMPI Settings" },
    .{ .name = "theme", .helper = "koompi-theme", .usage = "koompi theme [regenerate|mode|scheme|color] ...", .summary = "Apply or change the desktop theme" },
    .{ .name = "wallpaper", .helper = "koompi-wallpaper", .usage = "koompi wallpaper <command> ...", .summary = "Manage workspace wallpapers" },
    .{ .name = "display", .helper = "koompi-displays", .usage = "koompi display place <monitor> <direction> [anchor]", .summary = "Arrange displays" },
    .{ .name = "windows", .helper = "koompi-stacking", .usage = "koompi windows [toggle|on|off|status|clamp|cascade|maximize]", .summary = "Control tiling and stacking mode" },
    .{ .name = "preview", .helper = "koompi-quicklook", .usage = "koompi preview <path|close|kind|drive|install|selftest> ...", .summary = "Open or configure Quick Look" },
    .{ .name = "reload", .helper = "koompi-reload", .usage = "koompi reload", .summary = "Reload Hyprland and restart the shell" },
    .{ .name = "workbench", .helper = "koompi-workbench", .usage = "koompi workbench [project]", .summary = "Open the agent workbench" },
    .{ .name = "signature", .helper = "koompi-signature", .usage = "koompi signature <capture|from|install-okular|list> ...", .summary = "Capture and install document signatures" },
    .{ .name = "migrate", .helper = "koompi-migrate", .usage = "koompi migrate [--apply]", .summary = "Preview or apply packaged-default migration" },
};

const aliases = [_]struct { name: []const u8, target: []const u8 }{
    .{ .name = "status", .target = "health" },
    .{ .name = "displays", .target = "display" },
    .{ .name = "stacking", .target = "windows" },
    .{ .name = "quicklook", .target = "preview" },
};

const help_text =
    \\KOOMPI Desktop command line
    \\
    \\Usage:
    \\  koompi <command> [arguments]
    \\  koompi help [command]
    \\  koompi --version
    \\
    \\System:
    \\  update       Update packages or the installed checkout
    \\  doctor       Check the desktop session and its services
    \\  health       Alias for doctor
    \\  reload       Reload Hyprland and restart the shell
    \\  paths        Show KOOMPI config, data, state, and update paths
    \\  version      Show CLI version
    \\
    \\Desktop:
    \\  settings     Open KOOMPI Settings
    \\  theme        Apply or change the desktop theme
    \\  wallpaper    Manage workspace wallpapers
    \\  display      Arrange displays
    \\  windows      Control tiling and stacking mode
    \\
    \\Tools:
    \\  preview      Open or configure Quick Look
    \\  workbench    Open the agent workbench
    \\  signature    Capture and install document signatures
    \\  migrate      Preview or apply packaged-default migration
    \\  completion   Print completion for bash, zsh, or fish
    \\
    \\Run `koompi help <command>` for command-specific usage.
    \\The old `koompi-update` command remains compatible.
    \\
;

const command_names = "update doctor health reload paths version settings theme wallpaper display windows preview workbench signature migrate completion help";

const bash_completion =
    \\_koompi() {
    \\    local current="${COMP_WORDS[COMP_CWORD]}"
    \\    if (( COMP_CWORD == 1 )); then
    \\        COMPREPLY=( $(compgen -W "update doctor health reload paths version settings theme wallpaper display windows preview workbench signature migrate completion help" -- "$current") )
    \\    fi
    \\}
    \\complete -F _koompi koompi
    \\
;

const zsh_completion =
    \\#compdef koompi
    \\_arguments '1:command:(update doctor health reload paths version settings theme wallpaper display windows preview workbench signature migrate completion help)' '*::argument:->args'
    \\
;

const fish_completion =
    \\complete -c koompi -f
    \\complete -c koompi -n '__fish_use_subcommand' -a 'update doctor health reload paths version settings theme wallpaper display windows preview workbench signature migrate completion help'
    \\
;

fn writeOut(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, bytes);
}

fn writeErr(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, bytes);
}

fn findCommand(name: []const u8) ?*const Command {
    var resolved = name;
    for (aliases) |alias| {
        if (std.mem.eql(u8, name, alias.name)) {
            resolved = alias.target;
            break;
        }
    }
    for (&commands) |*command| {
        if (std.mem.eql(u8, resolved, command.name)) return command;
    }
    return null;
}

fn commandHelp(gpa: std.mem.Allocator, io: std.Io, name: []const u8) !u8 {
    const command = findCommand(name) orelse {
        const message = try std.fmt.allocPrint(gpa, "koompi: unknown command '{s}'\nRun `koompi --help` to list commands.\n", .{name});
        defer gpa.free(message);
        try writeErr(io, message);
        return 2;
    };
    const message = try std.fmt.allocPrint(gpa, "{s}\n\n{s}\n", .{ command.usage, command.summary });
    defer gpa.free(message);
    try writeOut(io, message);
    return 0;
}

fn pathExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(io, path, .{ .execute = true }) catch return false;
    return true;
}

fn updateHelper(init: std.process.Init) ![]u8 {
    const gpa = init.gpa;
    const env = init.environ_map;

    if (env.get("KOOMPI_UPDATE_HELPER")) |path| {
        if (pathExists(init.io, path)) return gpa.dupe(u8, path);
    }

    if (env.get("XDG_DATA_HOME")) |data_home| {
        const path = try std.fmt.allocPrint(gpa, "{s}/koompi/libexec/update", .{data_home});
        if (pathExists(init.io, path)) return path;
        gpa.free(path);
    }

    if (env.get("HOME")) |home| {
        const path = try std.fmt.allocPrint(gpa, "{s}/.local/share/koompi/libexec/update", .{home});
        if (pathExists(init.io, path)) return path;
        gpa.free(path);
    }

    if (pathExists(init.io, "/usr/lib/koompi/update")) {
        return gpa.dupe(u8, "/usr/lib/koompi/update");
    }
    return error.UpdateHelperNotFound;
}

fn runHelper(init: std.process.Init, helper: []const u8, rest: []const []const u8) !u8 {
    var argv: std.ArrayListUnmanaged([]const u8) = .empty;
    defer argv.deinit(init.gpa);
    try argv.append(init.gpa, helper);
    try argv.appendSlice(init.gpa, rest);

    var child = std.process.spawn(init.io, .{
        .argv = argv.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| switch (err) {
        error.FileNotFound => {
            const message = try std.fmt.allocPrint(init.gpa, "koompi: required helper not found: {s}\nRun `koompi doctor` for installation details.\n", .{helper});
            defer init.gpa.free(message);
            try writeErr(init.io, message);
            return 127;
        },
        else => |other| return other,
    };

    const term = try child.wait(init.io);
    return switch (term) {
        .exited => |code| code,
        .signal => |signal| @intCast(@min(255, 128 + @intFromEnum(signal))),
        .stopped, .unknown => 1,
    };
}

fn showVersion(io: std.Io) !u8 {
    try writeOut(io, "KOOMPI Desktop CLI " ++ version ++ "\n");
    return 0;
}

fn showPaths(init: std.process.Init) !u8 {
    const env = init.environ_map;
    const home = env.get("HOME") orelse "<unset>";
    const config_env = env.get("XDG_CONFIG_HOME");
    const data_env = env.get("XDG_DATA_HOME");
    const state_env = env.get("XDG_STATE_HOME");
    const config = if (config_env) |path|
        path
    else
        try std.fmt.allocPrint(init.gpa, "{s}/.config", .{home});
    defer if (config_env == null) init.gpa.free(config);
    const data = if (data_env) |path|
        path
    else
        try std.fmt.allocPrint(init.gpa, "{s}/.local/share", .{home});
    defer if (data_env == null) init.gpa.free(data);
    const state = if (state_env) |path|
        path
    else
        try std.fmt.allocPrint(init.gpa, "{s}/.local/state", .{home});
    defer if (state_env == null) init.gpa.free(state);

    const message = try std.fmt.allocPrint(init.gpa,
        \\config  {s}/koompi
        \\shell   {s}/quickshell/koompi
        \\data    {s}/koompi
        \\state   {s}/koompi
        \\repo    {s}/koompi/repo-path
        \\
    , .{ config, config, data, state, state });
    defer init.gpa.free(message);
    try writeOut(init.io, message);
    return 0;
}

fn showCompletion(io: std.Io, args: []const []const u8) !u8 {
    if (args.len != 1) {
        try writeErr(io, "Usage: koompi completion <bash|zsh|fish>\n");
        return 2;
    }
    if (std.mem.eql(u8, args[0], "bash")) {
        try writeOut(io, bash_completion);
    } else if (std.mem.eql(u8, args[0], "zsh")) {
        try writeOut(io, zsh_completion);
    } else if (std.mem.eql(u8, args[0], "fish")) {
        try writeOut(io, fish_completion);
    } else {
        try writeErr(io, "koompi: completion shell must be bash, zsh, or fish\n");
        return 2;
    }
    return 0;
}

fn execute(init: std.process.Init, args: []const []const u8) !u8 {
    if (args.len == 0) {
        try writeOut(init.io, help_text);
        return 0;
    }

    const name = args[0];
    if (std.mem.eql(u8, name, "--help") or std.mem.eql(u8, name, "-h")) {
        try writeOut(init.io, help_text);
        return 0;
    }
    if (std.mem.eql(u8, name, "--version") or std.mem.eql(u8, name, "-V") or std.mem.eql(u8, name, "version")) {
        return showVersion(init.io);
    }
    if (std.mem.eql(u8, name, "help")) {
        if (args.len == 1) {
            try writeOut(init.io, help_text);
            return 0;
        }
        return commandHelp(init.gpa, init.io, args[1]);
    }
    if (std.mem.eql(u8, name, "paths")) return showPaths(init);
    if (std.mem.eql(u8, name, "completion")) return showCompletion(init.io, args[1..]);

    const command = findCommand(name) orelse {
        const message = try std.fmt.allocPrint(init.gpa, "koompi: unknown command '{s}'\nAvailable commands: {s}\n", .{ name, command_names });
        defer init.gpa.free(message);
        try writeErr(init.io, message);
        return 2;
    };

    if (args.len > 1 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))) {
        return commandHelp(init.gpa, init.io, command.name);
    }

    if (std.mem.eql(u8, command.helper, "@update")) {
        const helper = updateHelper(init) catch {
            try writeErr(init.io,
                \\koompi: update helper not found
                \\Reinstall KOOMPI Desktop or run the legacy bootstrap:
                \\  curl -fsSL https://raw.githubusercontent.com/rithythul/koompi-desktop/main/install.sh | bash -s -- --no-apps --yes
                \\
            );
            return 127;
        };
        defer init.gpa.free(helper);
        return runHelper(init, helper, args[1..]);
    }
    return runHelper(init, command.helper, args[1..]);
}

pub fn main(init: std.process.Init) !void {
    var iterator = std.process.Args.Iterator.init(init.minimal.args);
    _ = iterator.next();

    var args: std.ArrayListUnmanaged([]const u8) = .empty;
    defer args.deinit(init.gpa);
    while (iterator.next()) |arg| try args.append(init.gpa, arg);

    const code = try execute(init, args.items);
    if (code != 0) std.process.exit(code);
}

test "command lookup includes aliases" {
    try std.testing.expectEqualStrings("display", findCommand("displays").?.name);
    try std.testing.expectEqualStrings("windows", findCommand("stacking").?.name);
    try std.testing.expectEqualStrings("preview", findCommand("quicklook").?.name);
    try std.testing.expect(findCommand("not-a-command") == null);
}

test "all public helper commands have usage and summary" {
    for (commands) |command| {
        try std.testing.expect(command.name.len > 0);
        try std.testing.expect(command.helper.len > 0);
        try std.testing.expect(std.mem.startsWith(u8, command.usage, "koompi "));
        try std.testing.expect(command.summary.len > 0);
    }
}

test "help advertises every public command" {
    for (commands) |command| {
        try std.testing.expect(std.mem.indexOf(u8, help_text, command.name) != null);
    }
}
