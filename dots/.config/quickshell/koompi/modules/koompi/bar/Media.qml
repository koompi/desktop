import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Hyprland

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property bool hasMedia: (activePlayer?.trackTitle ?? "").length > 0
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle)

    Layout.fillHeight: true
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: Appearance.sizes.barHeight
    // The spectrum below is drawn to the full item and would otherwise spill
    // over the group's rounded background.
    clip: true

    // Subtle spectrum behind the transport. WaveVisualizer already fills at 0.15
    // alpha and blurs itself, so it reads as texture on the bar rather than as a
    // second widget competing with the title.
    WaveVisualizer {
        z: -1
        points: Cava.points
        live: root.activePlayer?.isPlaying ?? false
        color: Appearance.colors.colPrimary
        // Heavier than the popup's default and barely blurred: this is a 63px
        // strip with no art beneath it, so the popup's settings vanish here.
        fillAlpha: 0.55
        blurAmount: 0.35
        // cava's ascii range is 0-1000 but ordinary listening sits well under
        // half of it, so scaling to the full range leaves the wave flat against
        // the bottom edge. Loud passages clip at the top of the strip, which for
        // a background texture is the right trade.
        maxVisualizerValue: 380
    }

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton) {
                activePlayer.togglePlaying();
            } else if (event.button === Qt.BackButton) {
                activePlayer.previous();
            } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
                activePlayer.next();
            } else if (event.button === Qt.LeftButton) {
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
            }
        }
    }

    RowLayout { // Real content
        id: rowLayout

        spacing: 4
        anchors.fill: parent

        ClippedFilledCircularProgress {
            id: mediaCircProg
            Layout.alignment: Qt.AlignVCenter
            lineWidth: Appearance.rounding.unsharpen
            value: activePlayer?.position / activePlayer?.length
            implicitSize: 20
            colPrimary: Appearance.colors.colOnSecondaryContainer
            enableAnimation: false

            Item {
                anchors.centerIn: parent
                width: mediaCircProg.implicitSize
                height: mediaCircProg.implicitSize
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: activePlayer?.isPlaying ? "pause" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        StyledText { // Trimmed track title; hidden entirely when no player (icon only)
            visible: root.hasMedia
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true // shrink + elide when the bar constrains us, instead of overrunning
            Layout.maximumWidth: 150
            Layout.rightMargin: rowLayout.spacing
            elide: Text.ElideRight
            color: Appearance.colors.colOnLayer1
            text: root.cleanedTitle
        }

    }

}
