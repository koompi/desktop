import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft.aiChat.feedback
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick.Layouts

/**
 * Everything the correction loop knows, in one place: how well it has been
 * doing, what disagrees with what the user asserted, what has been suppressed,
 * and which corrections stuck. `qs ipc call aifeedback toggle` opens it.
 */
PanelWindow {
    id: window

    required property var service

    visible: true
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: Appearance.colors.colScrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:aiFeedback"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea {
        anchors.fill: parent
        onClicked: event => {
            const local = card.mapFromItem(null, event.x, event.y);
            if (local.x < 0 || local.y < 0 || local.x > card.width || local.y > card.height) window.service.closePanel();
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        implicitWidth: Math.min(640, window.width - Appearance.sizes.elevationMargin * 8)
        implicitHeight: Math.min(760, window.height - Appearance.sizes.elevationMargin * 8)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh

        focus: true
        Keys.onEscapePressed: window.service.closePanel()

        ColumnLayout {
            anchors {
                fill: parent
                margins: Appearance.spacing.large
            }
            spacing: Appearance.spacing.normal

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Corrections")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }

                IconToolbarButton {
                    Layout.fillHeight: false
                    implicitHeight: 28
                    text: "close"
                    onClicked: window.service.closePanel()
                    StyledToolTip { text: Translation.tr("Close") }
                }
            }

            StyledFlickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: content.implicitHeight
                clip: true

                ColumnLayout {
                    id: content
                    width: parent.width
                    spacing: Appearance.spacing.normal

                    TrustRecoveryCard {
                        Layout.fillWidth: true
                    }

                    /* ---- conflicts ---- */

                    StyledText {
                        Layout.fillWidth: true
                        visible: window.service.openConflicts.length > 0
                        text: Translation.tr("WHAT DISAGREES WITH YOU")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }

                    Repeater {
                        model: window.service.openConflicts

                        delegate: Rectangle {
                            id: conflictCard
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: conflictLayout.implicitHeight + Appearance.spacing.normal * 2
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2
                            border.width: 2
                            border.color: Appearance.colors.colError

                            ColumnLayout {
                                id: conflictLayout
                                anchors {
                                    fill: parent
                                    margins: Appearance.spacing.normal
                                }
                                spacing: Appearance.spacing.small

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("You told me: %1").arg(conflictCard.modelData.asserted)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer2
                                    wrapMode: Text.Wrap
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Memory %1 says: %2")
                                        .arg(conflictCard.modelData.incomingId)
                                        .arg(conflictCard.modelData.incoming)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.Wrap
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Yours wins. It was not overwritten and it will not be.")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colError
                                    wrapMode: Text.Wrap
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Appearance.spacing.small

                                    Item { Layout.fillWidth: true }

                                    DialogButton {
                                        buttonText: Translation.tr("Keep both")
                                        onClicked: window.service.resolveConflict(conflictCard.modelData.key, false)
                                    }

                                    DialogButton {
                                        buttonText: Translation.tr("Delete the other one")
                                        colText: Appearance.colors.colError
                                        onClicked: window.service.resolveConflict(conflictCard.modelData.key, true)
                                    }
                                }
                            }
                        }
                    }

                    /* ---- suppressed sources ---- */

                    StyledText {
                        Layout.fillWidth: true
                        visible: window.service.activeSuppressions.length > 0
                        text: Translation.tr("STOPPED SURFACING")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }

                    Repeater {
                        model: window.service.activeSuppressions

                        delegate: Rectangle {
                            id: suppressedCard
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: suppressedLayout.implicitHeight + Appearance.spacing.normal
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            RowLayout {
                                id: suppressedLayout
                                anchors {
                                    fill: parent
                                    margins: Appearance.spacing.small
                                }
                                spacing: Appearance.spacing.small

                                StyledText {
                                    Layout.fillWidth: true
                                    text: `${String(suppressedCard.modelData.type).toUpperCase()} · ${suppressedCard.modelData.name}`
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    maximumLineCount: 2
                                }

                                DialogButton {
                                    buttonText: Translation.tr("Surface again")
                                    onClicked: window.service.unsuppressSource(suppressedCard.modelData.key)
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: window.service.activeSuppressions.length > 0
                        text: Translation.tr("Suppressed sources are excluded from retrieval, not deleted. The memory stays yours.")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                    }

                    /* ---- what stuck ---- */

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("WHAT YOU TAUGHT ME")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: window.service.corrections.length === 0
                        text: Translation.tr("Nothing corrected yet. Use “This is wrong” on an answer or on one of its sources.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: window.service.corrections.slice().reverse()

                        delegate: Rectangle {
                            id: correctionCard
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: correctionLayout.implicitHeight + Appearance.spacing.normal
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            ColumnLayout {
                                id: correctionLayout
                                anchors {
                                    fill: parent
                                    margins: Appearance.spacing.small
                                }
                                spacing: Appearance.spacing.small

                                StyledText {
                                    Layout.fillWidth: true
                                    text: correctionCard.modelData.statement
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colOnLayer2
                                    wrapMode: Text.Wrap
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: [
                                        correctionCard.modelData.mtype,
                                        Translation.tr("precedence %1").arg(correctionCard.modelData.precedence),
                                        correctionCard.modelData.origin,
                                        correctionCard.modelData.memoryId >= 0
                                            ? Translation.tr("memory %1").arg(correctionCard.modelData.memoryId)
                                            : (correctionCard.modelData.scope === "once"
                                                ? Translation.tr("this conversation only")
                                                : Translation.tr("not stored: %1").arg(correctionCard.modelData.memoryError))
                                    ].join(" · ")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.family: Appearance.font.family.monospace
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    /* ---- the habit table ---- */

                    StyledText {
                        Layout.fillWidth: true
                        visible: window.service.procedures.length > 0
                        text: Translation.tr("TOOL HABITS")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }

                    Repeater {
                        model: window.service.procedures

                        delegate: StyledText {
                            required property var modelData

                            Layout.fillWidth: true
                            text: `${modelData.tool_name} · ${modelData.input_pattern} · ${modelData.success_count}✓ ${modelData.failure_count}✗ · score ${window.service.actionScore(modelData).toFixed(2)}`
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Corrections, grounding and reports all stay on this machine · %1").arg(window.service.storeDir)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }
}
