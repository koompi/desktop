pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland

LockScreen {
    id: root

    lockSurface: LockSurface {
        context: root.context
    }

    // Monitor name -> workspace id to restore on unlock. Only monitors this
    // actually moved get an entry, so a monitor that was never pushed is never
    // "restored" to a workspace it was not on.
    property var savedWorkspaces: ({})

    function activeWorkspaceIdFor(screen) {
        // The live Hyprland object first; HyprlandData is a polled cache and is
        // briefly empty after a hot-plug or a compositor restart.
        const live = Hyprland.monitorFor(screen)?.activeWorkspace?.id;
        if (live !== undefined && live !== null)
            return live;
        const cached = HyprlandData.monitors?.find(m => m.name === screen.name)?.activeWorkspace?.id;
        return (cached !== undefined && cached !== null) ? cached : null;
    }

    // Move each monitor to a workspace far outside the usable range, so the
    // desktop is not sitting behind the lock surface waiting to be revealed by
    // a compositor bug. A monitor whose workspace is not known yet is skipped
    // and retried; it must not cost every other monitor its push.
    function pushMonitorsAway(screens) {
        var batch = "";
        var pending = [];
        var saved = root.savedWorkspaces;
        for (var i = 0; i < screens.length; ++i) {
            var screen = screens[i];
            if (saved[screen.name] !== undefined)
                continue;
            var workspaceId = root.activeWorkspaceIdFor(screen);
            if (workspaceId === null) {
                pending.push(screen);
                continue;
            }
            saved[screen.name] = workspaceId;
            batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${screen.name}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - workspaceId}})';`;
        }
        root.savedWorkspaces = saved;
        if (batch.length > 0)
            Quickshell.execDetached(["bash", "-c", batch]);
        return pending;
    }

    property var pendingScreens: []
    Timer {
        id: pushRetryTimer
        interval: 200
        repeat: true
        property int attemptsLeft: 0
        onTriggered: {
            root.pendingScreens = root.pushMonitorsAway(root.pendingScreens);
            attemptsLeft -= 1;
            if (root.pendingScreens.length === 0 || attemptsLeft <= 0)
                stop();
        }
    }

    // Clearing savedWorkspaces makes this idempotent, so calling it twice costs
    // nothing and the second caller is a safety net rather than a second move.
    function restoreMonitors() {
        pushRetryTimer.stop();
        root.pendingScreens = [];
        var batch = "";
        for (var i = 0; i < Quickshell.screens.length; ++i) {
            var name = Quickshell.screens[i].name;
            var workspaceId = root.savedWorkspaces[name];
            if (workspaceId === undefined)
                continue;
            batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${name}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${workspaceId}})';`;
        }
        root.savedWorkspaces = ({});
        if (batch.length > 0)
            Quickshell.execDetached(["bash", "-c", batch]);
    }

    // The password has been accepted but the surface is still up, which is the
    // only moment the desktop can be put back without the move being watched.
    onAboutToUnlock: root.restoreMonitors()

    // One batch for lock and one for unlock, so multiple hyprctl calls cannot
    // race each other into the wrong workspace.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                pushRetryTimer.stop();
                root.savedWorkspaces = ({});
                // Read which wallpaper each monitor is showing BEFORE moving
                // any of them, in the same handler, so no other connection can
                // run in between and read the pushed-away workspace instead.
                root.context.clearCapturedWallpapers();
                root.context.captureWallpapers(Quickshell.screens);
                root.pendingScreens = root.pushMonitorsAway(Quickshell.screens);
                if (root.pendingScreens.length > 0) {
                    pushRetryTimer.attemptsLeft = 5;
                    pushRetryTimer.restart();
                }
            } else {
                // Anything that clears the flag without going through the
                // unlock path still gets its workspaces back.
                root.restoreMonitors();
            }
        }
    }

    // A monitor plugged in while locked has no saved workspace, so it is pushed
    // now and restored with the rest.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (!GlobalStates.screenLocked)
                return;
            root.context.captureWallpapers(Quickshell.screens);
            root.pendingScreens = root.pushMonitorsAway(Quickshell.screens);
            root.context.shouldReFocus();
        }
    }
}
