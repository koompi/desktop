import qs.modules.common
import QtQuick

Rectangle {
    id: root
    property string key

    property real horizontalPadding: 3
    // The cap is a square, measured on the outside including its border and the
    // bottom lip. A monospace cell is 0.6 em against a 1.32 em line box, so a cap
    // sized off its glyph can only come out wider or taller than it is broad,
    // never square. Longer labels still grow sideways.
    property real keySize: 22
    // The mark inside it. KoompiStar inks 0.8 of its em, so the size the text
    // item has to run at for a 16px mark is 16 / 0.8; the metrics test pins that
    // 0.8 against the ttf so a rebuild cannot silently resize every keycap.
    property real glyphSize: 16
    readonly property real koompiInkPerEm: 0.8
    // Optical, not metric. The ttf centres its own ink on both axes and the test
    // holds it there; these are the pixel a geometrically centred mark needs to
    // stop reading high and left, the same way a cap sits low of centre against
    // round letters. Keep them constants. Anything that scales with the glyph is
    // the font drifting and belongs in build-font.py.
    property real glyphNudgeX: 1
    property real glyphNudgeY: 1
    property real borderWidth: 1
    property real extraBottomBorderWidth: 2
    property color borderColor: Appearance.colors.colOnLayer0
    property real borderRadius: 5
    property real pixelSize: Appearance.font.pixelSize.smaller
    property color keyColor: Appearance.m3colors.m3surfaceContainerLow
    // plane-16 codepoints exist only in KOOMPI Star
    readonly property bool koompiGlyph: key.codePointAt(0) >= 0x100000
    // The mark's cap is always the square. Its ink overhangs its cell, so Qt
    // reports a wider implicitWidth for it than for a letter and letting that
    // through would make the one cap that has to look like a key the one that
    // does not. Text caps still grow for longer labels.
    implicitWidth: koompiGlyph ? keySize
                               : Math.max(keyText.implicitWidth + horizontalPadding * 2 + borderWidth * 2, keySize)
    implicitHeight: keySize
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
        color: keyColor
        radius: borderRadius - borderWidth

        // KoompiStar carries JetBrains Mono NF's advance and line box and centres
        // its own ink, so the offsets below are the optical pixel and the size is
        // a deliberate icon size. Neither corrects the font.
        StyledText {
            id: keyText
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.koompiGlyph ? root.glyphNudgeX : 0
            anchors.verticalCenterOffset: root.koompiGlyph ? root.glyphNudgeY : 0
            font.family: root.koompiGlyph ? Appearance.font.family.iconKoompi : Appearance.font.family.monospace
            font.pixelSize: root.koompiGlyph ? root.glyphSize / root.koompiInkPerEm : root.pixelSize
            text: key
        }
    }
}
