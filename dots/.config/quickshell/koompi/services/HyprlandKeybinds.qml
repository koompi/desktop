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
 * Reads them from `hyprctl binds` and exposes description, key and modmask.
 */
Singleton {
    id: root
    property var keybinds: []
    property var keybindCategories: []

    // Deliberately not `hyprctl binds -j`. Hyprland 0.56.0 emits an
    // "auto_consuming" key in that object with no value behind it, so every
    // field from there on carries its neighbour's value and the result is not
    // even parseable JSON - `"keycode": SUPER_L` and an unquoted description.
    // JSON.parse threw, keybinds stayed empty, and the cheatsheet rendered
    // nothing. The plain-text form carries the same data and has been stable
    // for years, so it is the safer thing to depend on.
    //
    // Values may themselves contain a colon ("mouse:273", "Shell: Toggle
    // search"), so a line is split on its first colon only.
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

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getKeybinds.running = true
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
                root.keybinds = binds;
                root.keybindCategories = root.categoriesOf(binds);
            }
        }
    }
}
