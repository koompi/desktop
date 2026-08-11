import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * "This is wrong." (36:36-51)
 *
 * Sits on an answer and on every citation row. `source` is the row it belongs
 * to, or null when it disputes the whole answer; a row also offers "Stop
 * surfacing this", which excludes the source from retrieval without deleting
 * anything.
 */
RowLayout {
    id: root

    property string claim: ""
    property string messageId: ""
    property var source: null
    property bool showSuppress: root.source !== null

    readonly property bool suppressed: root.source !== null && Ai.isSourceSuppressed(root.source)

    spacing: Appearance.spacing.small

    RippleButton {
        id: wrongButton

        implicitHeight: 22
        implicitWidth: wrongRow.implicitWidth + Appearance.spacing.normal
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(Appearance.colors.colErrorContainer, 1)
        colBackgroundHover: Appearance.colors.colErrorContainer
        colRipple: Appearance.colors.colErrorContainer

        Accessible.name: Translation.tr("This is wrong")
        Accessible.description: root.source
            ? Translation.tr("Correct the fact this source was used for")
            : Translation.tr("Correct what the assistant just said")

        onClicked: Ai.openCorrection({
            "claim": root.claim,
            "messageId": root.messageId,
            "source": root.source
        })

        contentItem: RowLayout {
            id: wrongRow
            spacing: Appearance.spacing.small

            MaterialSymbol {
                text: "flag"
                iconSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
            }

            StyledText {
                text: Translation.tr("This is wrong")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: Appearance.colors.colError
            }
        }

        StyledToolTip {
            text: Translation.tr("Tell me the right fact. It becomes an asserted correction and outranks anything I infer later.")
        }
    }

    RippleButton {
        visible: root.showSuppress

        implicitHeight: 22
        implicitWidth: suppressRow.implicitWidth + Appearance.spacing.normal
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainerHighest, 1)
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
        colRipple: Appearance.colors.colSurfaceContainerHighest

        Accessible.name: root.suppressed
            ? Translation.tr("Surface this source again")
            : Translation.tr("Stop surfacing this source")

        onClicked: {
            if (root.suppressed) Ai.unsuppressSource(Ai.sourceKey(root.source));
            else Ai.suppressSource(root.source);
        }

        contentItem: RowLayout {
            id: suppressRow
            spacing: Appearance.spacing.small

            MaterialSymbol {
                text: root.suppressed ? "visibility" : "visibility_off"
                iconSize: Appearance.font.pixelSize.smaller
                color: root.suppressed ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            StyledText {
                text: root.suppressed ? Translation.tr("Suppressed") : Translation.tr("Stop surfacing this")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.suppressed ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
        }

        StyledToolTip {
            text: root.suppressed
                ? Translation.tr("Excluded from retrieval. The memory still exists — click to use it again.")
                : Translation.tr("Excluded from retrieval, not deleted. Reversible from the correction panel.")
        }
    }
}
