import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root

    property bool showPing: false

    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    visible: aiChatEnabled || translatorEnabled

    property real buttonPadding: 5
    // Padding alone leaves a 34px target on a 40px bar; floor it at bar height.
    implicitWidth: Math.max(Appearance.sizes.baseBarHeight, distroIcon.width + buttonPadding * 2)
    implicitHeight: Math.max(Appearance.sizes.baseBarHeight, distroIcon.height + buttonPadding * 2)
    // How far the icon sits inside the button box. The bar subtracts it so the
    // glyph, not the box, lines up with the clock at the other end.
    readonly property real iconInset: (implicitWidth - distroIcon.width) / 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarLeftOpen

    onPressed: {
        GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    CustomIcon {
        id: distroIcon
        anchors.centerIn: parent
        // keep even: centerIn a 40px button halves the remainder, and an odd
        // size lands the glyph on a half pixel and softens the blade gaps
        width: 26
        height: 26
        source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
        colorize: true
        color: Appearance.colors.colOnLayer0

        Rectangle {
            opacity: root.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2
                rightMargin: -2
            }
            implicitWidth: 8
            implicitHeight: 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
