import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * One memory: what it says, what kind it is, how strong it is, when it was last
 * recalled and where it came from. Click the text to edit it in place.
 */
Rectangle {
    id: root

    required property var entry
    // The rule `prune` gives for retiring this row, or "" when it keeps it.
    property string rejectReason: ""
    property real score: NaN
    property bool editing: false

    signal deleteRequested
    signal editAccepted(string text)

    readonly property string group: MemoryService.groupOf(root.entry.mtype)
    readonly property bool junk: root.rejectReason.length > 0

    implicitHeight: layout.implicitHeight + Appearance.spacing.normal * 2
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2
    border.width: root.junk ? 2 : 1
    border.color: root.junk ? Appearance.colors.colError : Appearance.colors.colOutlineVariant

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    function relativeTime(epochSeconds) {
        if (!epochSeconds || epochSeconds <= 0) return Translation.tr("never");
        const seconds = Math.max(0, Math.floor(Date.now() / 1000) - epochSeconds);
        if (seconds < 60) return Translation.tr("just now");
        if (seconds < 3600) return Translation.tr("%1 min ago").arg(Math.floor(seconds / 60));
        if (seconds < 86400) return Translation.tr("%1 h ago").arg(Math.floor(seconds / 3600));
        return Translation.tr("%1 d ago").arg(Math.floor(seconds / 86400));
    }

    ColumnLayout {
        id: layout
        anchors {
            fill: parent
            margins: Appearance.spacing.normal
        }
        spacing: Appearance.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            Rectangle { // type chip
                implicitWidth: typeLabel.implicitWidth + Appearance.spacing.normal
                implicitHeight: typeLabel.implicitHeight + Appearance.spacing.hairline * 2
                radius: Appearance.rounding.full
                color: root.group === "USER" ? Appearance.colors.colPrimaryContainer : root.group === "PROJECT" ? Appearance.colors.colTertiaryContainer : root.group === "FEEDBACK" ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest

                StyledText {
                    id: typeLabel
                    anchors.centerIn: parent
                    text: (root.entry.mtype ?? "fact").toUpperCase()
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: root.group === "USER" ? Appearance.colors.colOnPrimaryContainer : root.group === "PROJECT" ? Appearance.colors.colOnTertiaryContainer : root.group === "FEEDBACK" ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                }
            }

            StyledText {
                visible: !isNaN(root.score)
                text: Translation.tr("score %1").arg(isNaN(root.score) ? "" : root.score.toFixed(3))
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colPrimary
            }

            Item { Layout.fillWidth: true }

            IconToolbarButton {
                Layout.fillHeight: false
                implicitHeight: 26
                text: "edit"
                enabled: !root.editing
                onClicked: {
                    editor.text = root.entry.text;
                    root.editing = true;
                    editor.forceActiveFocus();
                }
                StyledToolTip { text: Translation.tr("Edit") }
            }

            IconToolbarButton {
                Layout.fillHeight: false
                implicitHeight: 26
                text: "delete"
                colText: Appearance.colors.colError
                onClicked: root.deleteRequested()
                StyledToolTip { text: Translation.tr("Delete this memory") }
            }
        }

        StyledText {
            id: textLabel
            visible: !root.editing
            Layout.fillWidth: true
            text: root.entry.text
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 4
            color: Appearance.colors.colOnLayer2

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: {
                    editor.text = root.entry.text;
                    root.editing = true;
                    editor.forceActiveFocus();
                }
            }
        }

        ColumnLayout {
            visible: root.editing
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            // The whole text has to be reachable without the 4 KB rows pushing
            // every other entry off the screen.
            StyledFlickable {
                id: editorFlickable
                Layout.fillWidth: true
                implicitHeight: Math.min(editor.implicitHeight, 220)
                contentWidth: width
                contentHeight: editor.implicitHeight
                clip: true

                StyledTextArea {
                    id: editor
                    width: editorFlickable.width
                    wrapMode: TextArea.Wrap
                    background: Rectangle {
                        radius: Appearance.rounding.verysmall
                        color: Appearance.colors.colLayer1
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.editing = false;
                            event.accepted = true;
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Saving rewrites the entry: memd has no update op, so it gets a new id and a fresh strength.")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: root.editing = false
                }

                DialogButton {
                    buttonText: Translation.tr("Save")
                    enabled: editor.text.trim().length > 0 && editor.text !== root.entry.text
                    onClicked: {
                        root.editing = false;
                        root.editAccepted(editor.text.trim());
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: [
                Translation.tr("strength %1").arg((root.entry.strength ?? 0).toFixed(2)),
                Translation.tr("recalled %1×").arg(root.entry.access_cnt ?? 0),
                Translation.tr("last recall %1").arg(root.relativeTime(root.entry.last_accessed)),
                Translation.tr("from %1").arg(root.entry.source && root.entry.source.length > 0 ? root.entry.source : Translation.tr("unknown"))
            ].join("  ·  ")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        RowLayout {
            visible: root.junk
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            MaterialSymbol {
                text: "warning"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colError
            }

            StyledText {
                Layout.fillWidth: true
                text: root.rejectReason
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colError
                wrapMode: Text.Wrap
            }
        }
    }
}
