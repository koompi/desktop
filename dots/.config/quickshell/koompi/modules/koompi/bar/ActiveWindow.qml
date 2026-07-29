import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Item { // Faux global menu: app icon + bold app name + window title
    id: root
    property alias globalMenuOpen: globalMenu.menuOpen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property var activeWindow: HyprlandData.activeWindow
    property bool focusingThisMonitor: root.activeWindow?.monitor === root.monitor?.id
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    readonly property bool hasWindow: root.focusingThisMonitor && (root.activeWindow?.mapped ?? false)
    readonly property string appClass: root.hasWindow ? (root.activeWindow?.class ?? "") : ((root.biggestWindow?.class) ?? "")
    readonly property string windowTitle: root.hasWindow ? (root.activeWindow?.title ?? "") : ((root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`)

    function prettyName(s) {
        if (!s || s.length === 0)
            return Translation.tr("Desktop");
        var n = String(s).split('.').pop().replace(/[-_]/g, ' ');
        return n.replace(/\b\w/g, function (c) {
            return c.toUpperCase();
        });
    }

    function cleanTitle(s) {
        if (!s)
            return "";
        // Strip leading whitespace + symbol/icon code points (Braille, arrows, BMP PUA,
        // variation selectors) and astral-plane glyphs (emoji / supplementary-PUA Nerd Font
        // icons, which arrive as UTF-16 surrogate pairs). \u escapes only - Qt's QML JS
        // engine has no \p{L} unicode-property support.
        var t = String(s).replace(/^[\s -⯿⸀-⹿-︀-️\uD800-\uDFFF]+/, "").trim();
        // Strip " - AppName" suffix (e.g. "Page - Google Chrome") case-insensitively.
        var name = root.prettyName(root.appClass).toLowerCase();
        if (name.length > 0 && name !== Translation.tr("Desktop").toLowerCase()) {
            var lower = t.toLowerCase();
            var seps = [" - ", " — ", " – "];
            for (var i = 0; i < seps.length; i++) {
                if (lower.endsWith(seps[i] + name)) {
                    t = t.slice(0, t.length - (seps[i] + name).length).trim();
                    break;
                }
            }
            // Hide row entirely if what remains is just the app name.
            if (t.toLowerCase() === name)
                return "";
        }
        return t;
    }

    implicitWidth: rowLayout.implicitWidth

    RowLayout {
        id: rowLayout

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        IconImage {
            id: appIcon
            implicitSize: 22
            Layout.alignment: Qt.AlignVCenter
            visible: root.appClass.length > 0 && status === Image.Ready
            source: Quickshell.iconPath(AppSearch.guessIcon(root.appClass), "")
        }

        ColumnLayout { // Two stacked rows: app name + menu over window title
            Layout.fillWidth: true
            spacing: -4

            RowLayout { // App name followed by inline global menu items
                Layout.fillWidth: true
                spacing: 6

                StyledText { // App name, menubar-style
                    id: appName
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                    elide: Text.ElideRight
                    text: root.prettyName(root.appClass)
                }

                GlobalMenu { // Inline File/Edit/View menu buttons
                    id: globalMenu
                    Layout.fillHeight: true
                    visible: root.focusingThisMonitor && menuItems.length > 0
                    // On a narrow bar the menu yields to the app name and icon;
                    // whatever is left over goes into its overflow button.
                    maxWidth: root.width - appIcon.width - appName.implicitWidth - 24
                }
            }

            StyledText { // Window title, dimmed
                Layout.fillWidth: true
                visible: text.length > 0
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                text: root.cleanTitle(root.windowTitle)
            }
        }
    }
}
