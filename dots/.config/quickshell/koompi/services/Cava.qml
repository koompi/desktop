pragma Singleton
pragma ComponentBehavior: Bound

// Audio spectrum, shared. Two surfaces draw it now - the media controls popup and
// the right sidebar's player card - and cava is a process reading the audio
// monitor, so each one owning its own would mean two of them whenever both are
// open. Which surfaces want it is declared here rather than counted, because a
// reference count leaks the moment a consumer is destroyed without decrementing.

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // The bar's media strip is on screen for the whole of any playback and draws
    // the spectrum behind itself, so cava now runs for the whole of it too. That
    // is the cost of a live visualiser on the bar; the alternative is a strip
    // whose background only moves while a panel happens to be open.
    readonly property bool wanted: GlobalStates.mediaControlsOpen
        || MprisController.hasActiveMedia

    property list<real> points: []

    Process {
        id: cavaProc
        running: root.wanted
        // Points have to be dropped on stop, or the visualizer freezes mid-bar
        // and reads as a live spectrum of silence.
        onRunningChanged: {
            if (!cavaProc.running)
                root.points = [];
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                root.points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }
}
