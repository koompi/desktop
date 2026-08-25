pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Renders LaTeX snippets with MicroTeX.
 * For every request:
 *   1. Hash it
 *   2. Check if the hash is already processed
 *   3. If not, render it with MicroTeX and mark as processed
 */
Singleton {
    id: root
    
    readonly property var renderPadding: 4 // This is to prevent cutoff in the rendered images

    property list<string> processedHashes: []
    property var processedExpressions: ({})
    property var renderedImagePaths: ({})
    property string microtexBinaryDir: "/opt/MicroTeX"
    property string microtexBinaryName: "LaTeX"
    property string latexOutputPath: Directories.latexOutput

    signal renderFinished(string hash, string imagePath)

    /**
    * Requests rendering of a LaTeX expression.
    * Returns the [hash, isNew]
    */
    function requestRender(expression) {
        // 1. Hash it and initialize necessary variables
        const hash = Qt.md5(expression)
        const imagePath = `${latexOutputPath}/${hash}.svg`
        
        // 2. Check if the hash is already processed
        if (processedHashes.includes(hash)) {
            // console.log("Already processed: " + hash)
            renderFinished(hash, imagePath)
            return [hash, false]
        } else {
            root.processedHashes.push(hash)
            root.processedExpressions[hash] = expression
            // console.log("Rendering expression: " + expression)
        }

        // 3. If not, render it with MicroTeX and mark as processed
        // argv, no shell: quotes, newlines and backslashes pass untouched
        microtexProcess.createObject(root, {
            hash: hash,
            imagePath: imagePath,
            command: [
                `${root.microtexBinaryDir}/${root.microtexBinaryName}`, "-headless",
                `-input=${expression}`,
                `-output=${imagePath}`,
                `-textsize=${Appearance.font.pixelSize.normal}`,
                `-padding=${renderPadding}`,
                `-foreground=${Appearance.colors.colOnLayer1}`,
                "-maxwidth=0.85"
            ]
        })
        return [hash, true]
    }

    Component {
        id: microtexProcess
        Process {
            id: proc
            required property string hash
            required property string imagePath
            running: true
            workingDirectory: root.microtexBinaryDir // res/ is loaded relative to cwd
            stderr: StdioCollector { id: errCollector }
            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0) {
                    root.renderedImagePaths[proc.hash] = proc.imagePath
                    root.renderFinished(proc.hash, proc.imagePath)
                } else {
                    // forget the hash so the next request retries
                    console.warn(`[LatexRenderer] MicroTeX exited with code ${exitCode}: ${errCollector.text.trim()}`)
                    root.processedHashes = root.processedHashes.filter(h => h !== proc.hash)
                }
                proc.destroy()
            }
        }
    }
}
