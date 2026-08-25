pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Emojis.
 */
Singleton {
    id: root
    property string emojiDataPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.txt`
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<var> list
    readonly property var preparedEntries: list.map(a => ({
        name: Fuzzy.prepare(`${a}`),
        entry: a
    }))
    function fuzzyQuery(search: string): var {
        if (root.sloppySearch) {
            const results = root.list.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function load() {
        emojiFileView.reload()
    }

    function updateEmojis(fileContent) {
        root.list = fileContent.split("\n").map(line => line.trim()).filter(line => line !== "")
        if (root.list.length === 0) console.warn(`No emoji entries in ${root.emojiDataPath}`)
    }

    FileView { 
        id: emojiFileView
        path: Qt.resolvedUrl(root.emojiDataPath)
        onLoadedChanged: {
            const fileContent = emojiFileView.text()
            root.updateEmojis(fileContent)
        }
    }
}
