import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The search surface. It owns GlobalStates.searchOpen and reads no other panel's
// flag, so opening or closing the workspace grid never moves this window.
Scope {
    id: root

    // Both surfaces keep the quickshell:overview layer namespace: the no_anim
    // layer rule that stops a full-screen layer from animating is written
    // against that name in hyprland/rules.lua.
    readonly property string layerNamespace: "quickshell:overview"

    function open() {
        searchWidget.cancelSearch();
        GlobalStates.searchOpen = true;
        searchWidget.focusSearchInput();
    }

    function openWithQuery(query) {
        searchWidget.setSearchingText(query);
        searchWidget.focusFirstItem();
        GlobalStates.searchOpen = true;
        searchWidget.focusSearchInput();
    }

    function close() {
        GlobalStates.searchOpen = false;
    }

    function toggle() {
        if (GlobalStates.searchOpen)
            root.close();
        else
            root.open();
    }

    // Clipboard and emoji are search modes. A mode toggles only itself, so
    // pressing the other one rewrites the query instead of closing the window.
    function toggleMode(prefix) {
        if (GlobalStates.searchOpen && searchWidget.searchingText.startsWith(prefix)) {
            root.close();
            return;
        }
        root.openWithQuery(prefix);
    }

    function toggleClipboard() {
        root.toggleMode(Config.options.search.prefix.clipboard);
    }

    function toggleEmojis() {
        root.toggleMode(Config.options.search.prefix.emojis);
    }

    PanelWindow {
        id: searchWindow
        visible: GlobalStates.searchOpen

        WlrLayershell.namespace: root.layerNamespace
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.searchOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: GlobalStates.searchOpen ? searchLayout : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        onVisibleChanged: {
            if (searchWindow.visible) {
                GlobalFocusGrab.addDismissable(searchWindow);
            } else {
                GlobalFocusGrab.removeDismissable(searchWindow);
                searchWidget.disableExpandAnimation();
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                root.close();
            }
        }

        implicitWidth: searchLayout.implicitWidth
        implicitHeight: searchLayout.implicitHeight

        Column {
            id: searchLayout
            visible: GlobalStates.searchOpen
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                }
            }

            SearchWidget {
                id: searchWidget
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            root.toggle();
        }
    }

    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            root.toggle();
        }
    }

    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "hyprland/keybinds.lua arms it with a catchall bind that fires for every key pressed while Super is held."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }

    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on search"

        onPressed: {
            root.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on search"

        onPressed: {
            root.toggleEmojis();
        }
    }
}
