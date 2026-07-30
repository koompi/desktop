pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common

// The focused window's own actions - close, float, fullscreen, pin, move to
// workspace - so none of them needs a keybinding to be found.
//
// The entries are rendered by GlobalMenuPopup, the same popup the application
// menu next door uses, because that file already solves placement against the
// bar, the focus grab over a chain of popup windows, and the keyboard path.
// Everything it asks of a menu is answered here: an entry tree, childrenOf,
// hasChildrenFor, send, registerPopup, unregisterPopup and handleKey.
Item {
    id: root

    /// The bar item the popup hangs from. Full bar height, so its bottom edge
    /// is the bar's edge and the popup's own offset is the whole gap.
    required property Item anchorItem

    /// The window the open menu acts on, taken when it opens. The popup takes
    /// the keyboard, so "whatever is focused now" stops being a safe answer
    /// the moment the menu is up.
    property var target: null
    readonly property bool menuOpen: root.target !== null

    function openFor(window) {
        if (!window?.address)
            return;
        root.target = window;
        root.forceActiveFocus();
    }

    function closeMenu() {
        root.target = null;
    }

    function toggleFor(window) {
        if (root.menuOpen)
            root.closeMenu();
        else
            root.openFor(window);
    }

    readonly property int workspacesShown: Config.options.bar.workspaces.shown

    readonly property var entries: {
        const win = root.target;
        if (!win)
            return [];
        const currentWorkspace = win.workspace?.id ?? 1;
        // The same group of ten the bar's workspace widget shows and the same
        // one Super+Alt+number moves into, so the list and the keys agree.
        const group = Math.floor((currentWorkspace - 1) / root.workspacesShown);
        const workspaces = [];
        for (let i = 1; i <= root.workspacesShown; i++) {
            const id = group * root.workspacesShown + i;
            workspaces.push({
                id: "workspace " + id,
                label: `${Translation.tr("Workspace")} ${id}`,
                // Super+Alt+number walks a group of ten. A different group size
                // would make the hint a lie, so it is only shown at ten.
                shortcut: root.workspacesShown === 10 ? `Super+Alt+${i % 10}` : "",
                toggle: true,
                checked: id === currentWorkspace,
                enabled: id !== currentWorkspace
            });
        }
        // Every entry carries `enabled` outright: the popup reads it as a hard
        // requirement, so an entry that leaves it out is neither clickable nor
        // reachable by the arrow keys.
        return [
            {
                id: "float",
                label: Translation.tr("Float"),
                shortcut: "Super+Alt+Space",
                toggle: true,
                checked: win.floating ?? false,
                enabled: true
            },
            {
                id: "fullscreen",
                label: Translation.tr("Fullscreen"),
                shortcut: "Super+F",
                toggle: true,
                checked: (win.fullscreen ?? 0) > 0,
                enabled: true
            },
            {
                id: "pin",
                label: Translation.tr("Pin above others"),
                shortcut: "Super+P",
                toggle: true,
                checked: win.pinned ?? false,
                // Hyprland pins floating windows only; a tiled window has
                // nothing to be pinned above.
                enabled: win.floating ?? false
            },
            {
                id: "workspace",
                label: Translation.tr("Move to workspace"),
                children: workspaces,
                enabled: true
            },
            {
                sep: true
            },
            {
                id: "close",
                label: Translation.tr("Close"),
                shortcut: "Super+Q",
                enabled: true
            }
        ];
    }

    function childrenOf(entry) {
        return entry?.children ?? [];
    }

    function hasChildrenFor(entry) {
        return (entry?.children?.length ?? 0) > 0;
    }

    /// The popup speaks the application menu's protocol. Only "activate" means
    /// anything here; "open" and "close" drive a D-Bus menu this does not have.
    function send(command) {
        if (!command.startsWith("activate "))
            return;
        root.run(command.slice("activate ".length));
    }

    function run(action) {
        const address = root.target?.address ?? "";
        if (!address)
            return;
        const selector = `window = "address:${address}"`;
        if (action === "close")
            Hyprland.dispatch(`hl.dsp.window.close({ ${selector} })`);
        else if (action === "float")
            Hyprland.dispatch(`hl.dsp.window.float({ action = "toggle", ${selector} })`);
        else if (action === "pin")
            Hyprland.dispatch(`hl.dsp.window.pin({ ${selector} })`);
        else if (action === "fullscreen") {
            // ponytail: fullscreen takes no window selector, so it acts on
            // whatever is focused. Focusing the target first is what makes it
            // act on the right window; drop the extra dispatch if the selector
            // ever lands.
            Hyprland.dispatch(`hl.dsp.focus({ ${selector} })`);
            Hyprland.dispatch(`hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })`);
        } else if (action.startsWith("workspace "))
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${action.slice("workspace ".length)}, follow = false, ${selector} })`);
    }

    // ── Focus chain ───────────────────────────────────────────────────────────

    /// Every window in the open chain. The grab has to cover all of them, or
    /// clicking the workspace submenu reads as a click outside and tears the
    /// menu down under the pointer.
    property var popupWindows: []

    function registerPopup(win) {
        if (!win || root.popupWindows.indexOf(win) >= 0)
            return;
        root.popupWindows = root.popupWindows.concat([win]);
    }

    function unregisterPopup(win) {
        const next = root.popupWindows.filter(w => w != null && w !== win);
        if (next.length !== root.popupWindows.length)
            root.popupWindows = next;
    }

    HyprlandFocusGrab {
        // Never active with an empty window list: the popup registers itself on
        // completion, and a grab over nothing clears itself immediately.
        active: root.menuOpen && root.popupWindows.length > 0
        windows: root.menuOpen ? [root.QsWindow.window].concat(root.popupWindows) : []
        onCleared: root.closeMenu()
    }

    Loader {
        id: popupLoader
        active: root.menuOpen && !!root.anchorItem

        sourceComponent: GlobalMenuPopup {
            rootEntries: root.entries
            menu: root
            anchorItem: root.anchorItem
            onDismissed: root.closeMenu()
        }
    }

    /// Every popup in the chain forwards keys here, because the compositor
    /// gives the keyboard to one window of the chain and which one that is
    /// changes as the submenu opens.
    function handleKey(key) {
        if (!root.menuOpen)
            return false;
        const chain = popupLoader.item;
        if (key === Qt.Key_Escape) {
            // Escape backs out of the submenu first, then closes the menu.
            if (chain && chain.closeDeepestChild())
                return true;
            root.closeMenu();
            return true;
        }
        if (key === Qt.Key_Left)
            return chain ? chain.closeDeepestChild() : false;
        if (key === Qt.Key_Right)
            return chain ? chain.openHighlightedChild() : false;
        return chain ? chain.handleKey(key) : false;
    }

    Keys.onPressed: event => {
        if (root.handleKey(event.key))
            event.accepted = true;
    }
}
