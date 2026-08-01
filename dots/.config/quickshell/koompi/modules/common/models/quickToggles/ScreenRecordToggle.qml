import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

QuickToggleModel {
    name: Translation.tr("Screen record")
    hasStatusText: false
    toggled: false
    icon: "videocam"

    // Close first: the recorder's own picker cannot appear under the sidebar.
    mainAction: () => {
        GlobalStates.sidebarRightOpen = false;
        delayedActionTimer.start();
    }
    Timer {
        id: delayedActionTimer
        interval: 300
        repeat: false
        onTriggered: Quickshell.execDetached([Directories.recordScriptPath])
    }

    tooltipText: Translation.tr("Screen record")
}
