import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * "Teach me the right fact." (36:66-86)
 *
 * What was said, struck through; what is true, typed; and the exact row that is
 * about to be written, shown before anything is written. Saving makes it an
 * asserted correction, which outranks anything inferred afterwards.
 */
Rectangle {
    id: root

    property var target: null
    signal closed()

    readonly property string claim: root.target?.claim ?? ""
    readonly property var source: root.target?.source ?? null
    readonly property string messageId: root.target?.messageId ?? ""

    // The record the save would write, recomputed on every keystroke, so the
    // preview below can never disagree with what lands.
    readonly property var draft: Ai.correctionDraft(input.text, root.claim)
    readonly property var provenance: root.draft ? Ai.correctionProvenance(root.draft) : null

    implicitHeight: layout.implicitHeight + Appearance.spacing.large * 2
    radius: Appearance.rounding.large
    color: Appearance.m3colors.m3surfaceContainerHigh
    border.width: 1
    border.color: Appearance.colors.colPrimary

    function focusInput() {
        input.text = root.target?.suggested ?? "";
        input.selectAll();
        input.forceActiveFocus();
    }

    ColumnLayout {
        id: layout
        anchors {
            fill: parent
            margins: Appearance.spacing.large
        }
        spacing: Appearance.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            MaterialSymbol {
                text: "school"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Teach me the right fact")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }

            IconToolbarButton {
                Layout.fillHeight: false
                implicitHeight: 28
                text: "close"
                onClicked: root.closed()
                StyledToolTip { text: Translation.tr("Close") }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.source !== null
            text: Translation.tr("About the source: %1").arg(root.source?.name ?? "")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }

        StyledText {
            text: Translation.tr("What I said")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: claimText.implicitHeight + Appearance.spacing.normal
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer2

            StyledText {
                id: claimText
                anchors {
                    fill: parent
                    margins: Appearance.spacing.small
                }
                text: root.claim.length > 0 ? root.claim : Translation.tr("(nothing quoted)")
                font.strikeout: root.claim.length > 0
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 4
            }
        }

        StyledText {
            text: Translation.tr("The correct fact")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            color: Appearance.colors.colPrimary
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(46, input.implicitHeight + Appearance.spacing.normal)
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer1
            border.width: 1.5
            border.color: Appearance.colors.colPrimary

            StyledTextArea {
                id: input
                anchors {
                    fill: parent
                    margins: Appearance.spacing.small
                }
                wrapMode: TextArea.Wrap
                placeholderText: Translation.tr("I am Rithy, not Nimmit")
                background: null
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.closed();
                        event.accepted = true;
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("This becomes an asserted fact. It will outrank anything I infer later.")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        // The provenance preview. It is drawn from the same object the write
        // uses, so what it says is what gets stored.
        Rectangle {
            id: provenanceRow
            Layout.fillWidth: true
            visible: root.provenance !== null
            implicitHeight: provenanceLayout.implicitHeight + Appearance.spacing.normal
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colSecondaryContainer

            RowLayout {
                id: provenanceLayout
                anchors {
                    fill: parent
                    margins: Appearance.spacing.small
                }
                spacing: Appearance.spacing.small

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: destLabel.implicitWidth + Appearance.spacing.small
                    implicitHeight: destLabel.implicitHeight + Appearance.spacing.hairline * 2
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colPrimary

                    StyledText {
                        id: destLabel
                        anchors.centerIn: parent
                        text: Translation.tr("→ MEMORY")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Writes “%1”").arg(root.provenance?.statement ?? "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: [
                            Translation.tr("to %1").arg(root.provenance?.store ?? ""),
                            Translation.tr("type %1").arg(root.provenance?.mtype ?? ""),
                            Translation.tr("precedence %1").arg(root.provenance?.precedence ?? ""),
                            Translation.tr("source %1").arg(root.provenance?.source ?? "")
                        ].join(" · ")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnSecondaryContainer
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: input.text.trim().length > 0 && root.provenance === null
            text: Translation.tr("I cannot turn that into a statement to store. Try a plain sentence, like “I am Rithy”.")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            DialogButton {
                buttonText: Translation.tr("Save a local report")
                colText: Appearance.colors.colSubtext
                onClicked: {
                    Ai.saveHallucinationReport(root.claim);
                    root.closed();
                }
                StyledToolTip {
                    text: Translation.tr("Writes a diagnostic bundle under ~/.local/share/koompi-ai/reports/. Never sent anywhere.")
                }
            }

            Item { Layout.fillWidth: true }

            DialogButton {
                buttonText: Translation.tr("Just this once")
                enabled: root.provenance !== null
                onClicked: {
                    Ai.applyCorrection(Object.assign({}, root.draft, {
                        "scope": "once",
                        "messageId": root.messageId,
                        "origin": "user-modal"
                    }), null);
                    root.closed();
                }
                StyledToolTip { text: Translation.tr("Use it for this conversation and do not store it") }
            }

            DialogButton {
                buttonText: Translation.tr("Save & remember")
                enabled: root.provenance !== null
                colText: Appearance.colors.colPrimary
                onClicked: {
                    Ai.applyCorrection(Object.assign({}, root.draft, {
                        "scope": "durable",
                        "messageId": root.messageId,
                        "origin": "user-modal"
                    }), null);
                    root.closed();
                }
            }
        }
    }
}
