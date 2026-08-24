import qs.modules.common
import QtQuick
import Quickshell

// Loads a user fork of a widget from ~/.config/koompi/plugins/<pluginId>/Widget.qml
// if one exists, falling back to the shipped `builtin` component otherwise. This is
// the only indirection BarContent.qml's call sites gain: no registry, no ordering,
// no enable/disable state - presence of Widget.qml on disk is the only signal.
//
// A missing or invalid plugin file resolves to Loader.status === Loader.Error rather
// than crashing the shell (verified live against this Quickshell build - see J07's
// report), so falling back to `builtin` below is safe.
Loader {
    id: root

    property string pluginId: ""
    property Component builtin: null

    readonly property string pluginWidgetPath: root.pluginId !== "" ? `${Directories.shellConfig}/plugins/${root.pluginId}/Widget.qml` : ""

    source: root.pluginWidgetPath !== "" ? Qt.resolvedUrl(root.pluginWidgetPath) : ""

    onStatusChanged: {
        if (root.status === Loader.Error) {
            root.source = "";
            root.sourceComponent = root.builtin;
        }
    }

    Component.onCompleted: {
        if (root.pluginWidgetPath === "") {
            root.sourceComponent = root.builtin;
        }
    }
}
