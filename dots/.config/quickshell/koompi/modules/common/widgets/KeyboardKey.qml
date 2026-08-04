import qs.modules.common
import QtQuick

Rectangle {
    id: root
    property string key

    property real horizontalPadding: 6
    property real verticalPadding: 1
    property real borderWidth: 1
    property real extraBottomBorderWidth: 2
    property color borderColor: Appearance.colors.colOnLayer0
    property real borderRadius: 5
    property real pixelSize: Appearance.font.pixelSize.smaller
    property color keyColor: Appearance.m3colors.m3surfaceContainerLow
    // plane-16 codepoints exist only in KOOMPI Star
    readonly property bool koompiGlyph: key.codePointAt(0) >= 0x100000
    // KoompiStar.ttf ink spans y -14..726 against hhea 800/-200, so its ink centre
    // sits 56/1000 em above the line-box centre that centerIn aligns. Push it back
    // down. tests/test_koompi_star_metrics.sh recomputes this from the ttf.
    readonly property real koompiGlyphRise: 0.056
    // The star's ink is 0.74 em against monospace's 0.73 em cap height, so at the
    // letters' size it draws the same height and reads smaller, the way a mark
    // among letters always does. 1.25 puts its ink at 0.93 em.
    readonly property real koompiGlyphScale: 1.25
    readonly property real koompiPixelSize: pixelSize * koompiGlyphScale
    implicitWidth: keyFace.implicitWidth + borderWidth * 2
    implicitHeight: keyFace.implicitHeight + borderWidth * 2 + extraBottomBorderWidth
    radius: borderRadius
    color: borderColor

    Rectangle {
        id: keyFace
        anchors {
            fill: parent
            topMargin: borderWidth
            leftMargin: borderWidth
            rightMargin: borderWidth
            bottomMargin: extraBottomBorderWidth + borderWidth
        }
        implicitWidth: (root.koompiGlyph ? monoRef.implicitWidth : keyText.implicitWidth) + horizontalPadding * 2
        implicitHeight: monoRef.implicitHeight + verticalPadding * 2
        color: keyColor
        radius: borderRadius - borderWidth

        StyledText {
            id: keyText
            anchors.centerIn: parent
            // Offset and size both off koompiPixelSize: the rise is a fraction of the
            // em, so scaling the glyph without scaling the rise re-opens the gap.
            anchors.verticalCenterOffset: root.koompiGlyph ? root.koompiPixelSize * root.koompiGlyphRise : 0
            font.family: root.koompiGlyph ? Appearance.font.family.iconKoompi : Appearance.font.family.monospace
            font.pixelSize: root.koompiGlyph ? root.koompiPixelSize : root.pixelSize
            text: key
        }

        // Both axes measured against a letter, not the star: its advance is a full
        // em against monospace's 0.6, and its line box is 1.0 em against 1.32, so
        // sizing the cap off the star gives a narrower and shorter cap than the rest.
        StyledText {
            id: monoRef
            visible: false
            font.family: Appearance.font.family.monospace
            font.pixelSize: root.pixelSize
            text: "W"
        }
    }
}
