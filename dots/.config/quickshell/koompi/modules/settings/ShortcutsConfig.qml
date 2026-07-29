pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property string searchText: ""
    property var keyBlacklist: ["SUPER_L", "SUPER_R"]
    property var keySubstitutions: ({
        "Super": "Super",
        "mouse_up": "Scroll ↓",
        "mouse_down": "Scroll ↑",
        "mouse:272": "LMB",
        "mouse:273": "RMB",
        "mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter"
    })

    function modMaskToStringList(modMask: int): list<string> {
        var list = [];
        if (modMask & (1 << 2)) { list.push("Ctrl"); }
        if (modMask & (1 << 6)) { list.push("Super"); }
        if (modMask & (1 << 0)) { list.push("Shift"); }
        if (modMask & (1 << 3)) { list.push("Alt"); }
        if (modMask & (1 << 1)) { list.push("Caps"); }
        if (modMask & (1 << 4)) { list.push("Mod2"); }
        if (modMask & (1 << 5)) { list.push("Mod3"); }
        if (modMask & (1 << 7)) { list.push("Mod5"); }
        return list;
    }

    function transformKey(key) {
        return root.keySubstitutions[key] || key;
    }

    function comboText(bind) {
        const mods = root.modMaskToStringList(bind?.modmask ?? 0);
        const key = bind?.key ?? "";
        if (root.keyBlacklist.includes(key)) return mods.join(" ");
        return [...mods, root.transformKey(key)].join(" ");
    }

    function transformDescription(bind, categoryName) {
        const description = bind?.description ?? "";
        if (categoryName.length === 0) return description;
        const regex = new RegExp("\\s*" + categoryName + "\\s*:\\s*");
        return description.replace(regex, "");
    }

    function isCategory(bind, categoryName) {
        const description = bind?.description ?? "";
        if (categoryName.length === 0) return description.indexOf(":") === -1;
        return description.substring(0, description.indexOf(":")) === categoryName;
    }

    function matchesSearch(bind) {
        const query = root.searchText.toLowerCase().trim();
        if (query.length === 0) return true;
        return root.comboText(bind).toLowerCase().includes(query)
            || (bind?.description ?? "").toLowerCase().includes(query);
    }

    function filteredBinds(categoryName) {
        return (HyprlandKeybinds.keybinds ?? []).filter(bind =>
            (bind?.description?.length ?? 0) > 0
            && root.isCategory(bind, categoryName)
            && root.matchesSearch(bind));
    }

    MaterialTextField {
        Layout.fillWidth: true
        placeholderText: Translation.tr("Search shortcuts")
        onTextChanged: root.searchText = text
    }

    Repeater {
        model: [...(HyprlandKeybinds.keybindCategories ?? []), ""]
        delegate: ContentSection {
            id: section
            required property var modelData
            readonly property string categoryName: section.modelData
            icon: "keyboard"
            title: section.categoryName.length > 0 ? Translation.tr(section.categoryName) : Translation.tr("Other")
            visible: bindRepeater.count > 0

            Repeater {
                id: bindRepeater
                model: root.filteredBinds(section.categoryName)
                delegate: ConfigRow {
                    id: bindRow
                    required property var modelData
                    readonly property var bind: bindRow.modelData

                    RowLayout {
                        spacing: 4
                        Repeater {
                            model: root.modMaskToStringList(bindRow.bind?.modmask ?? 0)
                            delegate: KeyboardKey {
                                required property var modelData
                                key: root.transformKey(modelData)
                            }
                        }
                        StyledText {
                            visible: !root.keyBlacklist.includes(bindRow.bind?.key ?? "") && (bindRow.bind?.modmask ?? 0) > 0
                            text: "+"
                        }
                        KeyboardKey {
                            visible: !root.keyBlacklist.includes(bindRow.bind?.key ?? "")
                            key: root.transformKey(bindRow.bind?.key ?? "")
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignRight
                        text: root.transformDescription(bindRow.bind, section.categoryName)
                    }
                }
            }
        }
    }

    StyledText {
        visible: root.searchText.trim().length > 0
            && [...(HyprlandKeybinds.keybindCategories ?? []), ""].every(category => root.filteredBinds(category).length === 0)
        text: Translation.tr("No shortcuts match your search")
        color: Appearance.colors.colSubtext
    }

    NoticeBox {
        Layout.fillWidth: true
        materialIcon: "info"
        text: Translation.tr("Shortcuts are configured in ~/.config/hypr/hyprland/keybinds.lua and custom/keybinds.lua. Press Super + / to view the cheatsheet anytime.")
    }
}
