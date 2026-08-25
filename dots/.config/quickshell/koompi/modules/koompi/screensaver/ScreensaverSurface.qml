import QtQuick
import Quickshell
import Quickshell.Wayland

// One screen of the idle layer. The black surface is the whole dim: the
// backlight is never written (the "No idle dim" note in hypridle.conf), so
// every slider and OSD keeps serving the value the shell last wrote.
PanelWindow {
    id: root

    signal dismiss

    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "black"
    WlrLayershell.namespace: "quickshell:screensaver"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand is all dismissal needs: the surface takes the keyboard when it
    // maps, so a key closes it, and compositor binds still pass through, so
    // Super+L still locks (and the lock replaces this layer).
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    ScreensaverContent {
        anchors.fill: parent
        onWake: root.dismiss()
    }
}
