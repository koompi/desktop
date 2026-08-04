import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * The workspace strip explaining itself, once, on a first run.
 *
 * Its own marker file rather than the first-run one: `first_run.txt` is written
 * the moment the shell greets you, so anything keyed to it has already missed
 * its chance. This one is written when the hint is dismissed, which is what
 * "never again after it is dismissed" asks for.
 */
LazyLoader {
    id: root

    // The workspaces widget, used to place the hint under it.
    property Item target

    readonly property string superKey: Config.options.cheatsheet.superKey || "󰖳"
    readonly property string markerPath: FileUtils.trimFileProtocol(`${Directories.state}/user/workspace_help_seen.txt`)
    // Shown only once the marker is known to be missing, so a slow or failed
    // read leaves the desktop as it was rather than popping a hint at someone
    // who has seen it.
    property bool dismissed: true

    active: Config.options.windows.workspaceHelp && !root.dismissed && root.target !== null

    function dismiss() {
        root.dismissed = true;
        root.marker.setText("Workspace hint shown and dismissed.\n");
    }

    // Named, or LazyLoader's `component` default property swallows it.
    property FileView marker: FileView {
        path: Qt.resolvedUrl(root.markerPath)
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.dismissed = false;
        }
    }

    component: PanelWindow {
        id: helpWindow
        color: "transparent"
        // The bar this hint belongs to, so a second monitor gets its own.
        screen: root.QsWindow?.screen ?? null

        readonly property bool vertical: Config.options.bar.vertical
        readonly property bool farSide: Config.options.bar.bottom

        anchors.left: !helpWindow.vertical || !helpWindow.farSide
        anchors.right: helpWindow.vertical && helpWindow.farSide
        anchors.top: helpWindow.vertical || !helpWindow.farSide
        anchors.bottom: !helpWindow.vertical && helpWindow.farSide

        implicitWidth: helpBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
        implicitHeight: helpBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

        mask: Region {
            item: helpBackground
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:workspaceHelp"
        WlrLayershell.layer: WlrLayer.Overlay
        // Nothing here is typed into, and taking focus on a first login would
        // pull the keyboard off whatever the user opened first.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // Clear the bar by the same distance a tiled window does, which is what
        // every other bar popup does. The elevation margin is shadow allowance
        // held inside this window, so it comes out of the offset.
        function barEdgeOffset(barExtent) {
            return barExtent - Appearance.sizes.elevationMargin + Appearance.sizes.hyprlandGapsOut + 1;
        }

        // The workspaces widget sits at the near end of its bar, so a hint
        // centred under it starts past the viewport edge - measured at x=-180
        // for a 380-wide surface, losing half the text. Layer-shell clips
        // instead of nudging, so the clamp has to happen here. Zero puts the
        // visible card an elevation margin in, since that margin is shadow
        // allowance held inside this window.
        function clampToScreen(offset, windowExtent, screenExtent) {
            return Math.min(Math.max(0, offset), Math.max(0, screenExtent - windowExtent));
        }
        margins {
            left: helpWindow.vertical
                ? helpWindow.barEdgeOffset(Appearance.sizes.verticalBarWidth)
                : helpWindow.clampToScreen(root.QsWindow?.mapFromItem(root.target, (root.target.width - helpBackground.implicitWidth) / 2, 0).x ?? 0, helpWindow.implicitWidth, helpWindow.screen?.width ?? 0)
            top: helpWindow.vertical
                ? helpWindow.clampToScreen(root.QsWindow?.mapFromItem(root.target, 0, (root.target.height - helpBackground.implicitHeight) / 2).y ?? 0, helpWindow.implicitHeight, helpWindow.screen?.height ?? 0)
                : helpWindow.barEdgeOffset(Appearance.sizes.barHeight)
            right: helpWindow.barEdgeOffset(Appearance.sizes.verticalBarWidth)
            bottom: helpWindow.barEdgeOffset(Appearance.sizes.barHeight)
        }

        StyledRectangularShadow {
            target: helpBackground
        }

        Rectangle {
            id: helpBackground
            anchors.fill: parent
            anchors.margins: Appearance.sizes.elevationMargin

            implicitWidth: helpColumn.implicitWidth + 20
            implicitHeight: helpColumn.implicitHeight + 20
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.small
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                id: helpColumn
                anchors.centerIn: parent
                spacing: 6

                RowLayout {
                    spacing: 8

                    MaterialSymbol {
                        text: "grid_view"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer1
                        text: Translation.tr("These are your workspaces")
                    }
                }

                StyledText {
                    Layout.maximumWidth: 340
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("Each one holds its own set of windows, so you can keep work in one and everything else in another.")
                }

                RowLayout {
                    Layout.topMargin: 2
                    spacing: 6

                    StyledText {
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Next one:")
                    }
                    KeyboardKey {
                        key: root.superKey
                    }
                    StyledText {
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: "+"
                    }
                    KeyboardKey {
                        key: Translation.tr("Page Down")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("or scroll here")
                    }
                }

                DialogButton {
                    Layout.alignment: Qt.AlignRight
                    Layout.topMargin: 2
                    buttonText: Translation.tr("Got it")
                    onClicked: root.dismiss()
                }
            }
        }
    }
}
