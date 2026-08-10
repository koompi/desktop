pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

/**
 * Hyprland data not available in Quickshell.Hyprland, from koompi-shelld.
 *
 * The daemon holds one socket2 subscription and queries only what an event invalidated,
 * where this file respawned all six `hyprctl -j` processes behind a 30 ms timer on every
 * event. The objects are the compositor's own JSON, field for field, so a consumer reads
 * them exactly as it read hyprctl's. See shell-services/shelld/PROTOCOL.md, the contract.
 */
Singleton {
    id: root

    readonly property var state: ShellServices.hyprland

    readonly property var windowList: root.state?.windows ?? []
    readonly property var addresses: root.windowList.map(win => win.address)
    readonly property var windowByAddress: {
        const byAddress = {};
        for (const win of root.windowList)
            byAddress[win.address] = win;
        return byAddress;
    }

    // The 1..100 subset. A special or lock-screen workspace carries an id outside it and
    // is not one this file ever published.
    readonly property var workspaces: root.state?.workspaces_numbered ?? []
    readonly property var workspaceIds: root.workspaces.map(ws => ws.id)
    readonly property var workspaceById: {
        const byId = {};
        for (const ws of root.workspaces)
            byId[ws.id] = ws;
        return byId;
    }
    readonly property var activeWorkspace: root.state?.active_workspace ?? null

    readonly property var activeWindow: root.state?.active_window ?? null
    readonly property var monitors: root.state?.monitors ?? []
    readonly property var layers: root.state?.layers ?? ({})

    // Convenient stuff

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const address = `0x${toplevel.HyprlandToplevel?.address}`;
            var win = HyprlandData.windowByAddress[address];
            return win?.workspace?.id === workspace;
        })
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    function clientForToplevel(toplevel) {
        if (!toplevel || !toplevel.HyprlandToplevel) {
            return null;
        }
        const address = `0x${toplevel?.HyprlandToplevel?.address}`;
        return root.windowByAddress[address];
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    /// The daemon pushes every change already. This is for a caller that cannot wait for
    /// the next one, such as the login-time "is anything open?" test in SessionRestore.
    function updateAll(): void {
        ShellServices.command("hyprland", "get_state");
    }

    Component.onCompleted: ShellServices.subscribe("hyprland")
}
