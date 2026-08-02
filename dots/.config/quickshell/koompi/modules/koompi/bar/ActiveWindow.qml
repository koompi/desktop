import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item { // Faux global menu: bold app name + window title
    id: root
    /// Whether either menu over this window is up. The bar takes keyboard focus
    /// on this, so both menus have to be in it or one of them gets no keys.
    readonly property bool menuOpen: globalMenu.menuOpen || actionsMenu.menuOpen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property var activeWindow: HyprlandData.activeWindow
    // Which output holds the keyboard, asked of Hyprland rather than inferred
    // from where the focused window sits. The window's monitor arrives through
    // polled hyprctl and lags, and it keeps naming the old output when focus
    // moves to a monitor with no windows on it, which left both bars claiming
    // the same one. Same source Workspaces.qml already reads.
    readonly property bool focusingThisMonitor: Hyprland.focusedMonitor?.id === root.monitor?.id
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    readonly property bool hasWindow: root.focusingThisMonitor && (root.activeWindow?.mapped ?? false)
    /// Whether clicking the app identity opens the window's own actions. Only a
    /// real focused window has actions to offer; the fallback identity of the
    /// biggest window on an unfocused monitor is a label, not a target.
    readonly property bool actionsAvailable: root.hasWindow && Config.options.windows.actionsMenu
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

    /// Cap on the app-identity block, so a very long window title elides instead
    /// of growing the left region under the centered workspaces. Derived from the
    /// screen rather than from this item's own width, which would bind back into
    /// the layout that sizes it.
    readonly property real identityMaxWidth: Math.max(160, Math.round((root.QsWindow.window?.screen?.width ?? 1920) * 0.18))

    implicitWidth: rowLayout.implicitWidth

    RowLayout {
        id: rowLayout

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        Item { // The identity block, and the window actions menu's pointer target
            id: identityBlock

            Layout.fillHeight: true
            // Full bar height whether or not the app menu beside it is showing,
            // because the popup below anchors to this item's bottom edge and
            // expects that edge to be the bar's.
            implicitHeight: Appearance.sizes.baseBarHeight
            implicitWidth: identityRow.implicitWidth

            Rectangle { // Same treatment the app menu titles get, so it reads as clickable
                anchors.centerIn: parent
                width: parent.width + 8
                height: Math.min(parent.height, 30)
                radius: Appearance.rounding.small
                color: root.actionsAvailable && (actionsMenu.menuOpen || identityHover.hovered) ? Appearance.colors.colLayer1Hover : "transparent"

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            HoverHandler {
                id: identityHover
                enabled: root.actionsAvailable
            }

            TapHandler {
                enabled: root.actionsAvailable
                onTapped: {
                    // Two menus over one window, one grab each: whichever is
                    // asked for wins and the other goes away.
                    globalMenu.closeMenu();
                    actionsMenu.toggleFor(root.activeWindow);
                }
            }

            RowLayout {
                id: identityRow
                anchors.fill: parent
                spacing: 6

                ColumnLayout { // App name stacked over window title, as one bounded block
                    id: identityColumn
                    // A nested layout stretches by default, so this block took the whole
                    // cap however short the app name was and pushed the menu a third of
                    // the screen to the right, up against the centered workspaces. Opting
                    // out of the stretch is what makes the preferred width below the
                    // width it actually gets.
                    Layout.fillWidth: false
                    // Wide enough for the text, never wider than the cap. Without an
                    // explicit floor the column inherits a minimum width from its text
                    // children, which outranks the cap and is why the title used to run
                    // on instead of eliding.
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: root.identityMaxWidth
                    Layout.preferredWidth: Math.min(identityColumn.implicitWidth, root.identityMaxWidth)
                    spacing: -4

                    StyledText { // App name, menubar-style
                        id: appName
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        // An unfocused monitor still shows its window, dimmed, so the
                        // focused one is tellable apart at a glance.
                        color: root.focusingThisMonitor ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnLayer1Inactive
                        elide: Text.ElideRight
                        text: root.prettyName(root.appClass)
                    }

                    StyledText { // Window title, dimmed
                        Layout.fillWidth: true
                        visible: text.length > 0
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.focusingThisMonitor ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1Inactive
                        elide: Text.ElideRight
                        text: root.cleanTitle(root.windowTitle)
                    }
                }
            }
        }

        GlobalMenu { // Inline File/Edit/View menu buttons, full bar height
            id: globalMenu
            Layout.fillHeight: true
            visible: root.focusingThisMonitor && menuItems.length > 0
            // The titles read as a menubar continuing the app name, so they sit on
            // the app-name row with the window title running under both. Only the
            // labels move: the item still spans the bar, so each title keeps the
            // bar-height pointer target it is clicked by.
            labelYOffset: identityBlock.y + identityColumn.y + appName.y + appName.height / 2 - (globalMenu.y + globalMenu.height / 2)
            // On a narrow bar the menu yields to the app name; whatever is left
            // over goes into its overflow button. Measured from the column's
            // implicit width, which does not depend on the layout.
            maxWidth: root.width - Math.min(identityColumn.implicitWidth, root.identityMaxWidth) - 24
        }

        Item { // Absorbs the leftover width, which a row of stretch-free items
            // would otherwise share out and open a gap between name and menu.
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    WindowActionsMenu { // Close, float, fullscreen, pin, move to workspace
        id: actionsMenu
        anchorItem: identityBlock
    }

    // The two menus sit side by side over the same window and each holds its
    // own focus grab, so opening one has to put the other away.
    Connections {
        target: globalMenu
        function onMenuOpenChanged() {
            if (globalMenu.menuOpen)
                actionsMenu.closeMenu();
        }
    }

    // The identity follows focus, so a menu left open would end up describing
    // one window and acting on another. Watching the address rather than the
    // window object, because HyprlandData hands out a fresh object on every
    // Hyprland event, a title change included.
    readonly property string activeAddress: root.activeWindow?.address ?? ""
    onActiveAddressChanged: {
        // Our own popup is a layer surface, and a grab can read as no active
        // window at all. That is not another window taking over.
        if (root.activeAddress.length > 0 && root.activeAddress !== actionsMenu.target?.address)
            actionsMenu.closeMenu();
    }
}
