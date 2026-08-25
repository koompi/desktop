pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

/**
 * Screensharing and mic activity.
 */
Singleton {
    id: root

    property bool screenSharing: Pipewire.linkGroups.values.some(pwlg => pwlg.source.type === PwNodeType.VideoSource)
    property bool micActive: Pipewire.linkGroups.values.some(pwlg => pwlg.source.type === PwNodeType.AudioSource && pwlg.target.type === PwNodeType.AudioInStream)
}
