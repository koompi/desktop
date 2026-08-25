pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * A service that provides access to Hyprland keybinds.
 * Reads them from `hyprctl binds` and exposes description, key and modmask,
 * and can run a bind the way its key would.
 */
Singleton {
    id: root
    property var keybinds: []
    property var keybindCategories: []

    // Hyprland's own override first, then the XDG default: the lookup Hyprland does.
    readonly property string configDir: {
        const override = Quickshell.env("HYPRLAND_CONFIG") ?? "";
        if (override.length > 0)
            return override.substring(0, override.lastIndexOf("/"));
        return FileUtils.trimFileProtocol(`${Directories.config}/hypr`);
    }
    // The modules hyprland.lua requires for binds, in its order.
    readonly property list<string> bindModules: ["hyprland.keybinds", "hyprland.keybinds_shell_extra", "custom.keybinds"]

    property var rawBinds: []
    // recordKey -> Lua expression, from the recorder. A Lua config reports every
    // bind as dispatcher `__lua` with an opaque index; the expression it was
    // declared with is the only thing `hyprctl dispatch` will run.
    property var recorded: ({})

    // Deliberately not `hyprctl binds -j`. Hyprland 0.56.0 emits a valueless
    // "auto_consuming" key, so every field from there on carries its neighbour's value
    // and the result is not parseable JSON. The plain-text form has been stable for
    // years.
    // Values may themselves contain a colon ("mouse:273"), so split on the first only.
    function parseBinds(text) {
        const binds = [];
        let current = null;

        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.length === 0)
                continue;

            if (line[0] !== "\t") {
                if (current)
                    binds.push(current);
                current = {
                    bindType: line.trim(),
                    modmask: 0,
                    submap: "",
                    key: "",
                    keycode: 0,
                    catchall: false,
                    description: "",
                    dispatcher: "",
                    arg: ""
                };
                continue;
            }

            if (!current)
                continue;

            const field = line.substring(1);
            const separator = field.indexOf(":");
            if (separator < 0)
                continue;

            const name = field.substring(0, separator);
            const value = field.substring(separator + 1).trim();

            if (name === "modmask" || name === "keycode")
                current[name] = parseInt(value, 10) || 0;
            else if (name === "catchall")
                current[name] = (value === "true");
            else if (current.hasOwnProperty(name))
                current[name] = value;
        }

        if (current)
            binds.push(current);

        return binds;
    }

    function categoriesOf(binds) {
        const groups = [];
        for (let i = 0; i < binds.length; i++) {
            const description = binds[i].description;
            const separator = description.indexOf(":");
            if (separator <= 0)
                continue;
            const group = description.substring(0, separator);
            if (!groups.includes(group))
                groups.push(group);
        }
        return groups;
    }

    // Funny mathematical order but we wanna have this natural user-facing order
    function modifiersOf(modmask: int): list<string> {
        const list = [];
        if (modmask & (1 << 2)) list.push("Ctrl");
        if (modmask & (1 << 6)) list.push("Super");
        if (modmask & (1 << 0)) list.push("Shift");
        if (modmask & (1 << 3)) list.push("Alt");
        if (modmask & (1 << 1)) list.push("Caps");
        if (modmask & (1 << 4)) list.push("Mod2");
        if (modmask & (1 << 5)) list.push("Mod3");
        if (modmask & (1 << 7)) list.push("Mod5");
        return list;
    }

    // Lua binds report the whole chord ("SUPER + ALT + code:10"); the modifiers are
    // already in modmask, the key is the last token.
    function keyOf(bind) {
        const separator = bind.key.lastIndexOf(" + ");
        const key = separator < 0 ? bind.key : bind.key.substring(separator + 3);
        if (key.length === 0 && bind.keycode > 0)
            return `code:${bind.keycode}`;
        return key;
    }

    function recordKey(modmask, key, submap, description) {
        return `${modmask}|${key.toLowerCase()}|${submap}|${description}`;
    }

    // What the search field matches against: chord, description and, through the
    // description's prefix, the category.
    function searchText(bind) {
        return `${root.modifiersOf(bind.modmask).join(" ")} ${root.keyOf(bind)} ${bind.description}`;
    }

    function dispatchable(bind) {
        if (!bind || bind.catchall || bind.submap.length > 0 || bind.dispatcher.length === 0)
            return false;
        // bindm: a drag or resize needs the button held
        if (bind.bindType.substring(4).includes("m"))
            return false;
        if (bind.dispatcher === "__lua")
            return (bind.expr ?? "").length > 0;
        return true;
    }

    // Under a Lua config `hyprctl dispatch` takes a Lua expression and nothing
    // else, so the recorded declaration is replayed as-is; a classic config gets
    // the classic form. An exec bind runs exactly the command the key runs, with
    // no wrapper of its own: the config already decides what goes through
    // koompi-launch, and wrapping again would double it.
    function dispatchArgv(bind) {
        if (!root.dispatchable(bind))
            return [];
        if (bind.dispatcher === "__lua")
            return ["hyprctl", "dispatch", bind.expr];
        if (bind.arg.length === 0)
            return ["hyprctl", "dispatch", bind.dispatcher];
        return ["hyprctl", "dispatch", bind.dispatcher, bind.arg];
    }

    function dispatch(bind) {
        const argv = root.dispatchArgv(bind);
        if (argv.length === 0)
            return false;
        Quickshell.execDetached(argv);
        return true;
    }

    function merge() {
        root.keybinds = root.rawBinds.map((bind, index) => Object.assign({}, bind, {
            id: index,
            expr: root.recorded[root.recordKey(bind.modmask, root.keyOf(bind), bind.submap, bind.description)] ?? ""
        }));
        root.keybindCategories = root.categoriesOf(root.keybinds);
    }

    function refresh() {
        getKeybinds.running = true;
        recordBinds.running = true;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                root.refresh();
            }
        }
    }

    Process {
        id: getKeybinds
        running: true
        command: ["hyprctl", "binds"]

        stdout: StdioCollector {
            onStreamFinished: {
                const binds = root.parseBinds(text);
                if (binds.length === 0) {
                    console.error("[CheatsheetKeybinds] hyprctl binds returned nothing usable");
                    return;
                }
                root.rawBinds = binds;
                root.merge();
            }
        }
    }

    Process {
        id: recordBinds
        running: true
        command: ["lua", Quickshell.shellPath("services/hyprlandKeybinds/recorder.lua"), root.configDir].concat(root.bindModules)

        stdout: StdioCollector {
            onStreamFinished: {
                let records = [];
                try {
                    records = JSON.parse(text);
                } catch (e) {
                    console.warn("[HyprlandKeybinds] bind recorder printed no usable JSON; Lua binds stay unclickable");
                }
                const recorded = {};
                records.forEach(record => {
                    if (record.expr === null)
                        return;
                    const key = root.recordKey(record.modmask, record.key, record.submap, record.description);
                    if (!(key in recorded))
                        recorded[key] = record.expr;
                });
                root.recorded = recorded;
                root.merge();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.warn("[HyprlandKeybinds] bind recorder: " + text.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn(`[HyprlandKeybinds] bind recorder exited ${exitCode}; some Lua binds may stay unclickable`);
        }
    }
}
