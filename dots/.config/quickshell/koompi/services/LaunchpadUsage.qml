pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Launch counts behind the Launchpad's ordering, so the apps actually reached
 * for surface on the first page instead of whatever sorts early by name.
 * Recency is folded into the score: a run of launches last month should not
 * outrank what is being used today.
 */
Singleton {
    id: root

    readonly property string filePath: `${Directories.state}/user/launchpad-usage.json`
    property alias counts: usageAdapter.counts
    property alias lastUsed: usageAdapter.lastUsed

    readonly property real dayMs: 86400000

    function score(appId) {
        if (!appId)
            return 0;
        const count = root.counts[appId] ?? 0;
        if (count === 0)
            return 0;
        const age = (Date.now() - (root.lastUsed[appId] ?? 0)) / root.dayMs;
        const weight = age < 1 ? 4 : age < 7 ? 2 : age < 30 ? 1 : 0.5;
        return count * weight;
    }

    // Both maps are reassigned rather than mutated in place: JsonAdapter only
    // notices a whole-property change, so an in-place write would never reach
    // disk.
    function record(appId) {
        if (!appId)
            return;
        const nextCounts = Object.assign({}, root.counts);
        nextCounts[appId] = (nextCounts[appId] ?? 0) + 1;
        usageAdapter.counts = nextCounts;

        const nextLast = Object.assign({}, root.lastUsed);
        nextLast[appId] = Date.now();
        usageAdapter.lastUsed = nextLast;
    }

    Timer {
        id: writeTimer
        interval: 400
        repeat: false
        onTriggered: usageFileView.writeAdapter()
    }

    FileView {
        id: usageFileView
        path: root.filePath
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeTimer.restart()
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound)
                writeTimer.restart();
        }

        adapter: JsonAdapter {
            id: usageAdapter
            property var counts: ({})
            property var lastUsed: ({})
        }
    }
}
