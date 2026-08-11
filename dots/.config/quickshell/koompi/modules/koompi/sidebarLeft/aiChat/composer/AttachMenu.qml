import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * What the composer can pick up from the desktop. Text lands in the input where
 * the user can read it before sending; an image can only be read by a model that
 * takes images, so the button says so rather than failing quietly.
 */
FlowButtonGroup {
    id: root

    signal insertText(string text)
    signal attachPath(string path)
    signal filePathRequested()

    property bool modelReadsImages: (Ai.getModel()?.api_format ?? "") === "gemini"
    property string shotPath: `${Directories.aiAttach}/region-${Math.floor(Date.now())}.png`

    // The sidebar takes keyboard focus, so the window the user means is the last
    // one that had it, not whatever is active while this menu is open.
    property var rememberedToplevel: null
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            if (ToplevelManager.activeToplevel)
                root.rememberedToplevel = ToplevelManager.activeToplevel;
        }
    }
    Component.onCompleted: {
        if (ToplevelManager.activeToplevel)
            root.rememberedToplevel = ToplevelManager.activeToplevel;
    }

    spacing: 5

    function focusFirst() {
        selectionButton.forceActiveFocus(Qt.TabFocusReason);
    }

    Process {
        id: selectionProc
        command: ["wl-paste", "--primary", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text;
                if (text.trim().length === 0) {
                    Ai.addMessage(Translation.tr("Nothing is selected right now."), Ai.interfaceRole);
                    return;
                }
                root.insertText("```text\n" + text + "\n```\n");
            }
        }
    }

    Process {
        id: regionShotProc
        // slurp then grim: one shell line, because the region has to be chosen
        // before the capture and neither tool can do both.
        command: ["bash", "-c", `mkdir -p "$(dirname '${root.shotPath}')" && grim -g "$(slurp -d)" '${root.shotPath}'`]
        onExited: exitCode => {
            if (exitCode === 0)
                root.attachPath(root.shotPath);
        }
    }

    ApiCommandButton {
        id: selectionButton
        buttonText: Translation.tr("Selection")
        Accessible.name: Translation.tr("Attach the selected text")
        onClicked: selectionProc.running = true
        StyledToolTip {
            text: Translation.tr("Whatever is selected in another window, as text")
        }
    }

    ApiCommandButton {
        buttonText: Translation.tr("This window")
        Accessible.name: Translation.tr("Attach the focused window's identity")
        onClicked: {
            const toplevel = root.rememberedToplevel;
            if (!toplevel) {
                Ai.addMessage(Translation.tr("No window is focused."), Ai.interfaceRole);
                return;
            }
            root.insertText(Translation.tr("Focused window: %1 - \"%2\"").arg(toplevel.appId ?? "?").arg(toplevel.title ?? "?") + "\n");
        }
        StyledToolTip {
            text: Translation.tr("The app id and title of the window you were last in")
        }
    }

    ApiCommandButton {
        buttonText: Translation.tr("Screenshot")
        Accessible.name: Translation.tr("Attach a screenshot of a region")
        onClicked: {
            root.shotPath = `${Directories.aiAttach}/region-${Math.floor(Date.now())}.png`;
            regionShotProc.running = true;
        }
        StyledToolTip {
            text: root.modelReadsImages
                ? Translation.tr("Drag a region. The image goes with your next message.")
                : Translation.tr("Drag a region. %1 cannot read images - switch to a model that can.").arg(Ai.getModel()?.name ?? "")
        }
    }

    ApiCommandButton {
        buttonText: Translation.tr("File…")
        Accessible.name: Translation.tr("Attach a file by path")
        onClicked: root.filePathRequested()
        StyledToolTip {
            text: Translation.tr("Type a path. Images and PDFs need a model that reads them.")
        }
    }
}
