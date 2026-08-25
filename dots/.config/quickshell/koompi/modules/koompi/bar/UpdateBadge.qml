import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Pending package updates (OMARCHY-AUDIT O09). Lit only while Updates knows of
 * some; the count rides next to the icon so the number is visible without a
 * hover. Click runs `koompi update` in a floating terminal, middle-click asks
 * checkupdates again.
 */
Revealer {
    id: root

    property real realSpacing: Appearance.spacing.large
    property color color: Appearance.colors.colOnLayer0
    readonly property var tooltipEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top

    // The terminal list is variables.lua's, in its order, and koompi-launch's
    // `--terminal` contract (CMD -e COMMAND) is what every entry answers to.
    // exec rules make the first window float; the read keeps the transcript on
    // screen until a key, so a failed update is not a window that vanished.
    readonly property string runUpdate: "exec [float;center;size 70% 70%] bash -c '"
        + 'for t in wezterm foot "kitty -1" alacritty konsole kgx uxterm xterm; do '
        + 'command -v "${t%% *}" >/dev/null 2>&1 || continue; '
        + 'exec koompi-launch --id koompi-update --terminal "${TERMINAL:-$t}" -- '
        + 'bash -c "koompi update; read -rsn1 -p \\"Done. Press any key to close.\\""; done; '
        + 'koompi-notify-send "No terminal installed" "Run koompi update from a shell"\''

    reveal: Updates.available && Updates.count > 0
    Layout.fillHeight: true
    Layout.rightMargin: reveal ? root.realSpacing : 0
    Behavior on Layout.rightMargin {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // No anchors: the indicator row is exactly one icon tall, so the badge
    // sits level with its neighbours at y 0 (anchoring here loops through the
    // Revealer's childrenRect).
    RowLayout {
        id: rowLayout
        spacing: 2

        MaterialSymbol {
            text: "system_update"
            iconSize: Appearance.font.pixelSize.larger
            color: root.color
        }
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: Updates.count
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.color
        }
    }

    MouseArea {
        id: badgeHover
        anchors.fill: rowLayout
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                Updates.refresh();
            else
                Hyprland.dispatch(root.runUpdate);
        }

        PopupToolTip {
            extraVisibleCondition: badgeHover.containsMouse
            anchorEdges: root.tooltipEdges
            text: Translation.tr("%1 updates — click to run `koompi update`, middle-click to check again").arg(Updates.count)
        }
    }
}
