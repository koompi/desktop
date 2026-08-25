pragma ComponentBehavior: Bound
import qs
import QtQuick
import Quickshell
import Quickshell.Io

// The branded idle layer (O32): black, the KOOMPI mark drifting, a small clock.
// hypridle is its only switch. Its 120 s listener in dots/.config/hypr/hypridle.conf
// calls `open` and its on-resume calls `close`; the layer also closes on its own
// input, and the lock at 300 s replaces it. Keep-awake needs no check here: with
// Idle.inhibit on, hypridle never reaches the timeout, so nothing calls `open`.
Scope {
    id: root

    function open() {
        // Nothing to show under a session lock: the compositor composites the
        // lock surface above every layer, and the lock is what replaces this.
        if (GlobalStates.screenLocked)
            return;
        GlobalStates.screensaverOpen = true;
    }

    function close() {
        GlobalStates.screensaverOpen = false;
    }

    function toggle() {
        if (GlobalStates.screensaverOpen)
            root.close();
        else
            root.open();
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                root.close();
        }
    }

    // Built per open rather than kept mapped: between idles no surface of this
    // layer exists, and the drift timer only runs while it is on screen. The
    // few hundred ms a fresh surface costs are invisible after minutes of idle.
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: surfaceLoader
            required property var modelData
            active: GlobalStates.screensaverOpen
            sourceComponent: ScreensaverSurface {
                screen: surfaceLoader.modelData
                onDismiss: root.close()
            }
        }
    }

    IpcHandler {
        target: "screensaver"

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        function toggle(): void {
            root.toggle();
        }
    }
}
