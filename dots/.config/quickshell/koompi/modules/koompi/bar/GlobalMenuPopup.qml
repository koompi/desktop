pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// One level of the global menu. A submenu loads this same file again through a
// Loader, because QML refuses to instantiate a type inside itself.
PopupWindow {
    id: popup

    required property var menu // the GlobalMenu root: daemon channel + patches
    required property Item anchorItem
    /// Set for a submenu: the item whose children this popup shows.
    property var parentEntry: null
    /// Set for the top level: the entries to show.
    property var rootEntries: []
    property bool submenu: false
    property int highlight: -1

    readonly property var entries: popup.parentEntry ? popup.menu.childrenOf(popup.parentEntry) : popup.rootEntries

    signal dismissed // an entry was activated: tear the whole chain down

    color: "transparent"
    visible: true

    // Top-level menus clear the roughly 40px panel before the command surface
    // begins. Nested menus stay tight to their parent row.
    // The top-level popup needs this positioning offset to clear the 40px
    // panel. Its resulting visible gap is about 3px.
    readonly property real panelOffset: 18
    readonly property real visibleGap: 5
    // The top-level surface starts where the title glyph starts (the bar title
    // has 10px of leading hit padding).
    readonly property real leadingPadding: popup.submenu ? popup.visibleGap : 10
    readonly property real trailingPadding: popup.submenu ? 2 : 3
    readonly property real topPadding: popup.submenu ? 0 : popup.panelOffset
    readonly property real bottomPadding: 16

    anchor {
        window: popup.anchorItem.QsWindow.window
        item: popup.anchorItem
        edges: popup.submenu ? (Edges.Right | Edges.Top) : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
        gravity: popup.submenu ? (Edges.Right | Edges.Bottom) : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
    }

    implicitWidth: background.implicitWidth + popup.leadingPadding + popup.trailingPadding
    implicitHeight: background.implicitHeight + popup.topPadding + popup.bottomPadding

    function activate(entry) {
        if (!entry || entry.sep || !entry.enabled)
            return;
        popup.menu.send("activate " + entry.id);
        popup.dismissed();
    }

    function moveHighlight(step) {
        const count = popup.entries.length;
        if (count === 0)
            return;
        let i = popup.highlight;
        for (let n = 0; n < count; n++) {
            i = (i + step + count) % count;
            const entry = popup.entries[i];
            if (!entry.sep && entry.enabled) {
                popup.highlight = i;
                return;
            }
        }
    }

    // The bar owns the focus grab for the whole chain and routes keys here; the
    // deepest open popup is the one that answers.
    function handleKey(key) {
        if (childLoader.item && childLoader.item.handleKey(key))
            return true;
        if (key === Qt.Key_Up) {
            popup.moveHighlight(-1);
            return true;
        }
        if (key === Qt.Key_Down) {
            popup.moveHighlight(1);
            return true;
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            // Nothing highlighted here (a submenu opened by hover, say) means
            // this level cannot answer; let an outer level try.
            const entry = popup.highlight >= 0 ? popup.entries[popup.highlight] : null;
            if (!entry)
                return false;
            if (popup.menu.hasChildrenFor(entry))
                return popup.openHighlightedChild();
            popup.activate(entry);
            return true;
        }
        return false;
    }

    /// Closes the innermost open submenu. Returns false once this popup is the
    /// innermost one, which is how Escape and Left know to leave the level.
    function closeDeepestChild() {
        if (childLoader.item && childLoader.item.closeDeepestChild())
            return true;
        if (!popup.childEntry)
            return false;
        popup.closeChild();
        return true;
    }

    /// Opens the highlighted entry's submenu in the innermost open popup.
    function openHighlightedChild() {
        if (childLoader.item && childLoader.item.openHighlightedChild())
            return true;
        if (popup.childEntry || popup.highlight < 0)
            return false;
        const entry = popup.entries[popup.highlight];
        if (!entry || !popup.menu.hasChildrenFor(entry))
            return false;
        const item = popup.entryItemAt(popup.highlight);
        if (!item)
            return false;
        popup.openChild(entry, item);
        if (childLoader.item)
            childLoader.item.moveHighlight(1);
        return true;
    }

    function entryItemAt(i) {
        for (let n = 0; n < entryColumn.children.length; n++) {
            const child = entryColumn.children[n];
            if (child.index === i)
                return child;
        }
        return null;
    }

    // At most one submenu is open per level, which is what keeps the chain a
    // chain rather than a spray of popups.
    property var childEntry: null

    function openChild(entry, item) {
        if (popup.childEntry === entry)
            return;
        popup.closeChild();
        popup.childEntry = entry;
        popup.menu.send("open " + entry.id);
        childLoader.setSource("GlobalMenuPopup.qml", {
            menu: popup.menu,
            anchorItem: item,
            parentEntry: entry,
            submenu: true
        });
    }

    function closeChild() {
        if (!popup.childEntry)
            return;
        popup.menu.send("close " + popup.childEntry.id);
        popup.childEntry = null;
        childLoader.setSource("");
        // The closed level's window took the keyboard; take it back here so a
        // second Escape or Left is not swallowed by a dead window.
        keyReceiver.forceActiveFocus();
    }

    // Each level is its own window, so the chain's focus grab has to list all of
    // them; a window the grab does not know about counts as "outside".
    Component.onCompleted: popup.menu.registerPopup(popup)
    Component.onDestruction: popup.menu.unregisterPopup(popup)

    // Keys only arrive at a window that has an item holding active focus, and
    // the compositor hands the keyboard to whichever window of the chain it
    // last focused, so every level listens and forwards to the same handler.
    Item {
        id: keyReceiver
        anchors.fill: parent
        focus: true
        Component.onCompleted: keyReceiver.forceActiveFocus()

        Keys.onPressed: event => {
            if (popup.menu.handleKey(event.key))
                event.accepted = true;
        }
    }

    Loader {
        id: childLoader
        onLoaded: item.dismissed.connect(popup.dismissed)
    }

    // A broad ambient shadow and a tighter contact shadow give the menu a
    // precise desktop elevation instead of the generic shell-card treatment.
    RectangularShadow {
        anchors.fill: background
        radius: background.radius
        blur: 24
        spread: -1
        offset: Qt.vector2d(0, 8)
        color: Qt.rgba(0, 0, 0, Appearance.m3colors.darkmode ? 0.42 : 0.24)
        cached: true
    }

    RectangularShadow {
        anchors.fill: background
        radius: background.radius
        blur: 8
        spread: 0
        offset: Qt.vector2d(0, 2)
        color: Qt.rgba(0, 0, 0, Appearance.m3colors.darkmode ? 0.34 : 0.18)
        cached: true
    }

    Rectangle {
        id: background
        readonly property real innerPadding: 4

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            leftMargin: popup.leadingPadding
            rightMargin: popup.trailingPadding
            topMargin: popup.topPadding
            bottomMargin: popup.bottomPadding
        }
        color: ColorUtils.applyAlpha(Appearance.colors.colLayer0Base, Appearance.m3colors.darkmode ? 0.96 : 0.94)
        radius: 10
        border.width: 1
        border.color: Appearance.m3colors.darkmode
            ? Qt.rgba(1, 1, 1, 0.16)
            : Qt.rgba(0, 0, 0, 0.16)
        clip: true

        implicitWidth: Math.max(152, Math.min(420, entryColumn.implicitWidth + innerPadding * 2))
        implicitHeight: entryColumn.implicitHeight + innerPadding * 2

        opacity: 0
        scale: 0.975
        transformOrigin: Item.TopLeft
        Component.onCompleted: {
            opacity = 1;
            scale = 1;
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 90
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 110
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 10
                rightMargin: 10
            }
            height: 1
            color: Appearance.m3colors.darkmode
                ? Qt.rgba(1, 1, 1, 0.08)
                : Qt.rgba(1, 1, 1, 0.72)
        }

        ColumnLayout {
            id: entryColumn
            anchors {
                fill: parent
                margins: background.innerPadding
            }
            spacing: 0

            Repeater {
                model: popup.entries

                delegate: GlobalMenuEntry {
                    id: entryItem
                    required property var modelData
                    required property int index

                    entry: modelData
                    menu: popup.menu
                    Layout.fillWidth: true
                    keyHighlighted: popup.highlight === index

                    onEntered: {
                        popup.highlight = index;
                        if (hasChildren)
                            popup.openChild(modelData, entryItem);
                        else
                            popup.closeChild();
                    }
                    onTriggered: popup.activate(modelData)
                    onOpenChildren: popup.openChild(modelData, entryItem)
                }
            }
        }
    }
}
