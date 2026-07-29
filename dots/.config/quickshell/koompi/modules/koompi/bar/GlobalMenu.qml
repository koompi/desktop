pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The focused window's menubar, inline in the bar. The daemon does all the
// D-Bus work and hands us a plain tree; we render it and send back
// "activate <id>" when something is clicked. Ids belong to the payload they
// arrived in, so anything open is closed when a new payload lands.
Item {
    id: root

    readonly property var menuItems: GlobalMenuService.menuItems
    property int openIdx: -1
    readonly property bool menuOpen: openIdx !== -1
    property int openedTopId: 0

    onMenuOpenChanged: {
        if (root.menuOpen)
            root.forceActiveFocus();
    }

    /// Width the bar can spare. A negative value means nobody has measured yet,
    /// so take what is needed; zero is a real answer from a bar with nothing
    /// left over, and has to end with everything in the overflow button rather
    /// than being read as "unlimited".
    property real maxWidth: -1
    readonly property bool widthLimited: root.maxWidth >= 0
    readonly property real widthBudget: Math.max(0, root.maxWidth)

    implicitWidth: {
        if (!root.widthLimited)
            return itemRow.implicitWidth;
        // The overflow button is the one thing that must always fit: without it
        // a squeezed bar would drop the whole menu with no way back to it.
        const floor = root.menuItems.length > 0 ? overflowButton.implicitWidth : 0;
        return Math.min(itemRow.implicitWidth, Math.max(root.widthBudget, floor));
    }
    implicitHeight: 22

    function send(command) {
        GlobalMenuService.send(command);
    }

    function childrenOf(entry) {
        return GlobalMenuService.childrenOf(entry);
    }

    /// Whether an entry opens a submenu. Qt applications build submenus only
    /// when told they are about to show, so an entry can be a submenu while its
    /// children are still empty; the daemon marks those with "sub".
    function hasChildrenFor(entry) {
        return GlobalMenuService.hasChildrenFor(entry);
    }

    function closeMenu() {
        root.openIdx = -1;
    }

    // Quickshell 0.2.1 can crash if a live PopupWindow's anchor item changes in
    // place. Tear down the old popup first, update the top-level selection on a
    // later event turn, then recreate the popup against the new stable anchor.
    function switchTopLevel(index) {
        if (root.openIdx === index)
            return;
        if (!root.menuOpen) {
            root.openIdx = index;
            return;
        }
        popupLoader.rebuilding = true;
        Qt.callLater(() => {
            root.openIdx = index;
            Qt.callLater(() => popupLoader.rebuilding = false);
        });
    }

    // Keep lazy top-level menus in sync while the pointer or keyboard moves
    // between File/Edit/View/etc. The Loader stays active during that switch,
    // so this cannot rely on Loader.onActiveChanged.
    function syncTopLevelOpen() {
        const nextId = root.openIdx >= 0 ? (root.menuItems[root.openIdx]?.id ?? 0) : 0;
        if (root.openedTopId > 0 && root.openedTopId !== nextId)
            root.send("close " + root.openedTopId);
        if (nextId > 0 && root.openedTopId !== nextId)
            root.send("open " + nextId);
        root.openedTopId = nextId;
    }

    onOpenIdxChanged: root.syncTopLevelOpen()

    /// How many top-level entries fit. Measuring implicit widths keeps this
    /// independent of what is currently visible, so hiding one cannot feed
    /// back into the calculation.
    readonly property int fitCount: {
        if (!root.widthLimited)
            return root.menuItems.length;
        if (root.widthBudget < overflowButton.implicitWidth)
            return 0;
        let used = 0;
        for (let i = 0; i < menuRepeater.count; i++) {
            const item = menuRepeater.itemAt(i);
            if (!item)
                return root.menuItems.length;
            used += item.implicitWidth;
            // Leave room for the overflow button when not everything fits.
            const budget = i === menuRepeater.count - 1 ? root.widthBudget : root.widthBudget - overflowButton.implicitWidth;
            if (used > budget)
                return i;
        }
        return root.menuItems.length;
    }

    // ── Focus chain ───────────────────────────────────────────────────────────

    /// Every window in the open chain, the top-level popup and each nested
    /// submenu. The grab has to cover all of them, or clicking a submenu reads
    /// as a click outside and tears the menu down under the pointer.
    property var popupWindows: []

    function registerPopup(win) {
        if (!win || root.popupWindows.indexOf(win) >= 0)
            return;
        root.popupWindows = root.popupWindows.concat([win]);
    }

    function unregisterPopup(win) {
        // Popups unregister while being destroyed, so drop anything already
        // gone in the same pass rather than handing the grab a dangling window.
        const next = root.popupWindows.filter(w => w != null && w !== win);
        if (next.length !== root.popupWindows.length)
            root.popupWindows = next;
    }

    Connections {
        target: GlobalMenuService
        function onMenuReset() {
            root.closeMenu();
        }
    }

    // Clicking anywhere outside the menu, or pressing Escape, closes it. The
    // owning bar remains part of the focus chain so focus-follows-mouse can
    // reach another top-level title before the chain is dismissed.
    HyprlandFocusGrab {
        id: focusGrab
        // Do not activate with an empty window list: the popup registers itself
        // on completion, avoiding an immediate outside-focus clear during load.
        active: root.menuOpen && root.popupWindows.length > 0
        windows: root.menuOpen
            ? [root.QsWindow.window].concat(root.popupWindows)
            : []
        onCleared: root.closeMenu()
    }

    Row {
        id: itemRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            id: menuRepeater
            model: root.menuItems

            delegate: GlobalMenuButton {
                required property var modelData
                required property int index

                label: modelData.label ?? ""
                opened: root.openIdx === index
                visible: index < root.fitCount
                onToggle: {
                    if (root.openIdx === index)
                        root.closeMenu();
                    else
                        root.switchTopLevel(index);
                }
                onHoverSwitch: {
                    if (root.menuOpen)
                        root.switchTopLevel(index);
                }
            }
        }

        GlobalMenuButton {
            id: overflowButton
            label: "…"
            visible: root.fitCount < root.menuItems.length
            opened: root.openIdx === -2
            onToggle: {
                if (root.openIdx === -2)
                    root.closeMenu();
                else
                    root.switchTopLevel(-2);
            }
            onHoverSwitch: {
                if (root.menuOpen)
                    root.switchTopLevel(-2);
            }
        }
    }

    // Exactly one popup chain is alive at a time, anchored to whichever
    // top-level button is open.
    Loader {
        id: popupLoader
        property bool rebuilding: false
        active: root.menuOpen && !!root.currentAnchor && !rebuilding

        readonly property var currentEntries: {
            if (root.openIdx === -2)
                return root.menuItems.slice(root.fitCount);
            const entry = root.menuItems[root.openIdx];
            return root.childrenOf(entry);
        }

        sourceComponent: GlobalMenuPopup {
            rootEntries: popupLoader.currentEntries
            menu: root
            anchorItem: root.currentAnchor
            onDismissed: root.closeMenu()
        }

    }

    readonly property Item currentAnchor: {
        if (root.openIdx === -2)
            return overflowButton;
        if (root.openIdx < 0)
            return null;
        return menuRepeater.itemAt(root.openIdx);
    }

    /// The top-level positions the arrow keys walk: the entries that fit, then
    /// the overflow button when there is one, so nothing is unreachable from
    /// the keyboard on a narrow bar.
    function topLevelPositions() {
        const out = [];
        for (let i = 0; i < root.fitCount; i++)
            out.push(i);
        if (root.fitCount < root.menuItems.length)
            out.push(-2);
        return out;
    }

    function stepTopLevel(step) {
        const positions = root.topLevelPositions();
        if (positions.length === 0)
            return;
        const at = positions.indexOf(root.openIdx);
        const next = at < 0 ? (step > 0 ? 0 : positions.length - 1) : (at + step + positions.length) % positions.length;
        root.switchTopLevel(positions[next]);
    }

    /// Every popup in the chain forwards keys here, because the compositor
    /// gives the keyboard to one window of the chain and which one that is
    /// changes as submenus open.
    function handleKey(key) {
        if (!root.menuOpen)
            return false;
        const chain = popupLoader.item;
        if (key === Qt.Key_Escape) {
            // Escape backs out one level at a time, then closes the menu.
            if (chain && chain.closeDeepestChild())
                return true;
            root.closeMenu();
            return true;
        }
        if (key === Qt.Key_Left) {
            if (chain && chain.closeDeepestChild())
                return true;
            root.stepTopLevel(-1);
            return true;
        }
        if (key === Qt.Key_Right) {
            if (chain && chain.openHighlightedChild())
                return true;
            root.stepTopLevel(1);
            return true;
        }
        return chain ? chain.handleKey(key) : false;
    }

    Keys.onPressed: event => {
        if (root.handleKey(event.key))
            event.accepted = true;
    }

    component GlobalMenuButton: Item {
        id: button
        property string label: ""
        property bool opened: false

        signal toggle
        signal hoverSwitch

        // A menu title is a small target; 10px of padding either side keeps it
        // clickable without the bar looking like a toolbar.
        implicitWidth: buttonLabel.implicitWidth + 20
        implicitHeight: Math.max(20, root.height)

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            radius: Appearance.rounding.small
            color: button.opened || hoverHandler.hovered ? Appearance.colors.colLayer1Hover : "transparent"

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnLayer0
        }

        HoverHandler {
            id: hoverHandler
            onHoveredChanged: if (hovered)
                button.hoverSwitch()
        }

        TapHandler {
            onTapped: button.toggle()
        }
    }
}
