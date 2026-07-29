import qs
import Quickshell
import Quickshell.Io

// Search and the workspace grid are two independent surfaces. Super opens
// search, Super+Tab opens the grid, and each one owns its own window, focus
// grab, and GlobalStates flag; neither is computed from the other.
Scope {
    id: overviewScope

    SearchPanel {
        id: searchPanel
    }

    OverviewPanel {
        id: overviewPanel
    }

    // One IPC target keeps the existing "search" contract, but each call routes
    // to the surface that owns it.
    IpcHandler {
        target: "search"

        function toggle() {
            searchPanel.toggle();
        }
        function workspacesToggle() {
            overviewPanel.toggle();
        }
        function close() {
            searchPanel.close();
        }
        function open() {
            searchPanel.open();
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            searchPanel.toggleClipboard();
        }
    }
}
