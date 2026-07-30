pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    required property Component lockSurface
    property alias context: lockContext

    // Raised once the password is accepted and before the surface goes away,
    // so anything that rearranged the desktop for the lock can undo it out of
    // sight.
    signal aboutToUnlock()

    // True from the moment the password is accepted until the surface is
    // dropped. The surface stays opaque for all of it: the lock takes its own
    // furniture away and settles onto the wallpaper it is already showing, so
    // the frame it disappears on is the frame the desktop appears with.
    // Nothing is ever revealed THROUGH this surface - a compositor that
    // animates the desktop back into place, or does not draw it at all, must
    // not be able to show either of those things.
    property bool unlocking: false
    // How long the surface has to take itself apart, and how long it then holds
    // the finished frame. The hold is what makes this read as smooth: without
    // it the surface is dropped while its own animation is still moving, and a
    // cut out of motion looks like a jump however short it is.
    readonly property int exitDuration: 350
    readonly property int exitHoldDuration: 120

    Timer {
        id: unlockDelayTimer
        // Also comfortably longer than the one hyprctl round trip the desktop
        // restore needs; shorter than that and the restore is still in flight
        // when the surface drops.
        interval: root.exitDuration + root.exitHoldDuration
        onTriggered: {
            // Unlock the screen before exiting, or the compositor will display
            // a fallback lock you can't interact with.
            GlobalStates.screenLocked = false;
            root.unlocking = false;
            lockContext.reset();
        }
    }
    property Component sessionLockSurface: WlSessionLockSurface {
        id: sessionLockSurface
        // Opaque for every frame it exists, including the first and the last. A
        // transparent lock surface lets the compositor show whatever is behind
        // it, which is exactly what this screen exists to prevent, and on the
        // way out it is also where the blink came from.
        color: Appearance.m3colors.m3background
        Loader {
            // Stays loaded for the whole unlock animation: `screenLocked` is
            // only cleared once the surface has finished settling.
            active: GlobalStates.screenLocked
            anchors.fill: parent
            // Read by the loaded surface as `parent.lockScreenName` and
            // `parent.lockUnlocking`: workspaces carry their own wallpapers, so
            // a surface has to know which screen it is on to show the right
            // one, and it animates its own exit because only it knows which of
            // its parts are furniture and which is the wallpaper that stays.
            readonly property string lockScreenName: sessionLockSurface.screen?.name ?? ""
            readonly property bool lockUnlocking: root.unlocking
            readonly property int lockExitDuration: root.exitDuration
            sourceComponent: root.lockSurface
        }
    }

    Process {
        id: unlockKeyringProc
        onExited: (exitCode, exitStatus) => {
            KeyringStorage.fetchKeyringData();
        }
    }
    function unlockKeyring() {
        unlockKeyringProc.exec({
            environment: ({
                "UNLOCK_PASSWORD": lockContext.currentText
            }),
            command: ["bash", "-c", Quickshell.shellPath("scripts/keyring/unlock.sh")]
        })
    }

    // This stores all the information shared between the lock surfaces on each screen.
    // https://github.com/quickshell-mirror/quickshell-examples/tree/master/lockscreen
    LockContext {
        id: lockContext

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    // A lock that arrives while a previous unlock is still
                    // fading must start from a fully drawn surface.
                    root.unlocking = false;
                    lockContext.reset();
                    lockContext.refreshCapsLock();
                    lockContext.tryFingerUnlock();
                }
            }
        }

        onUnlocked: (targetAction) => {
            // Perform the target action if it's not just unlocking
            if (targetAction == LockContext.ActionEnum.Poweroff) {
                Session.poweroff();
                return;
            } else if (targetAction == LockContext.ActionEnum.Reboot) {
                Session.reboot();
                return;
            }

            // Unlock the keyring if configured to do so
            if (Config.options.lock.security.unlockKeyring) root.unlockKeyring(); // Async

            // Post-unlock actions
            if (lockContext.alsoInhibitIdle) {
                lockContext.alsoInhibitIdle = false;
                Idle.toggleInhibit(true);
            }

            // Let whatever moved the desktop out of the way put it back while
            // this surface is still covering it, then unlock. Dropping the
            // surface first shows the bare workspace underneath for as long as
            // the restore takes.
            // Armed BEFORE the signal, never after: a handler that throws must
            // not be able to cost someone the only way out of the lock.
            unlockDelayTimer.restart();
            root.unlocking = true;
            root.aboutToUnlock();
        }
    }

    WlSessionLock {
        id: lock
        locked: GlobalStates.screenLocked
        surface: root.sessionLockSurface
    }

    function lock() {
        if (Config.options.lock.useHyprlock) {
            Quickshell.execDetached(["bash", "-c", "pidof hyprlock || hyprlock"]);
            return;
        }
        GlobalStates.screenLocked = true;
    }

    IpcHandler {
        target: "lock"

        function activate(): void {
            root.lock();
        }
        function focus(): void {
            lockContext.shouldReFocus();
        }
    }

    GlobalShortcut {
        name: "lock"
        description: "Locks the screen"

        onPressed: {
            root.lock()
        }
    }

    GlobalShortcut {
        name: "lockFocus"
        description: "Re-focuses the lock screen. This is because Hyprland after waking up for whatever reason"
            + "decides to keyboard-unfocus the lock screen"

        onPressed: {
            lockContext.shouldReFocus();
        }
    }

    function initIfReady() {
        if (!Config.ready || !Persistent.ready) return;
        if (Config.options.lock.launchOnStartup && Persistent.isNewHyprlandInstance) {
            root.lock();
        } else {
            KeyringStorage.fetchKeyringData();
        }
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.initIfReady();
        }
    }
    Connections {
        target: Persistent
        function onReadyChanged() {
            root.initIfReady();
        }
    }
}
