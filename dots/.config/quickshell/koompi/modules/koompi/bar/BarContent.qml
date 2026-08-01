import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Bar content region
    id: root

    readonly property bool menuOpen: activeWindow.menuOpen
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property real useShortenedForm: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2 : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (useShortenedForm == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened : (useShortenedForm == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth

    component VerticalBarSeparator: Rectangle {
        Layout.topMargin: Appearance.sizes.baseBarHeight / 3
        Layout.bottomMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillHeight: true
        implicitWidth: 1
        color: Appearance.colors.colOutlineVariant
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }
        color: Config.options.bar.showBackground ? Appearance.colors.colBarBackground : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    FocusedScrollMouseArea { // Left side | scroll to change brightness
        id: barLeftSideMouseArea
        // Clicks belong to the dedicated sidebar button and the global-menu
        // controls below. This parent exists only for hover and wheel input.
        acceptedButtons: Qt.NoButton

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: middleSection.left
        }
        implicitWidth: leftSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Brightness.decreaseBrightness()
        onScrollUp: Brightness.increaseBrightness()
        onMovedAway: GlobalStates.osdBrightnessOpen = false
        // Visual content
        ScrollHint {
            reveal: barLeftSideMouseArea.hovered
            icon: Hyprsunset.gamma === 100 ? "light_mode" : "wb_twilight"
            tooltipText: Translation.tr("Scroll to change brightness")
            side: "left"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: leftSectionRowLayout
            anchors.fill: parent
            spacing: 0

            LeftSidebarButton { // Left sidebar button
                id: leftSidebarButton
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: Appearance.rounding.screenRounding
                colBackground: barLeftSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
            }

            ActiveWindow {
                id: activeWindow
                Layout.leftMargin: Appearance.spacing.normal + (leftSidebarButton.visible ? 0 : Appearance.rounding.screenRounding)
                Layout.rightMargin: Appearance.rounding.screenRounding
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.useShortenedForm === 0
            }
        }
    }

    Row { // Middle section
        id: middleSection
        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        spacing: Appearance.spacing.small

        BarGroup {
            id: middleCenterGroup
            anchors.verticalCenter: parent.verticalCenter
            padding: workspacesWidget.widgetPadding

            Workspaces {
                id: workspacesWidget
                Layout.fillHeight: true
                MouseArea {
                    // Right-click to toggle overview
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton

                    onPressed: event => {
                        if (event.button === Qt.RightButton) {
                            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
                        }
                    }
                }

                WorkspaceHelp {
                    target: workspacesWidget
                }
            }
        }

    }

    FocusedScrollMouseArea { // Right side | scroll to change volume
        id: barRightSideMouseArea
        // Clicks belong to the dedicated sidebar button below, as on the left.
        // The whole strip used to toggle the right sidebar on top of that button,
        // so clicking the clock or the Pomodoro timer opened it, and opening it
        // times out and marks read every notification. This parent exists only
        // for hover and wheel input.
        acceptedButtons: Qt.NoButton

        anchors {
            top: parent.top
            bottom: parent.bottom
            left: middleSection.right
            right: parent.right
        }
        implicitWidth: rightSectionRowLayout.implicitWidth
        implicitHeight: Appearance.sizes.baseBarHeight

        onScrollDown: Audio.decrementVolume();
        onScrollUp: Audio.incrementVolume();
        onMovedAway: GlobalStates.osdVolumeOpen = false;

        // Visual content
        ScrollHint {
            reveal: barRightSideMouseArea.hovered
            icon: "volume_up"
            tooltipText: Translation.tr("Scroll to change volume")
            side: "right"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
        }

        RowLayout {
            id: rightSectionRowLayout
            anchors.fill: parent
            spacing: Appearance.spacing.normal
            layoutDirection: Qt.RightToLeft

            ClockWidget { // Time, far-right corner; date removed by default
                showDate: false
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: Appearance.rounding.screenRounding
            }

            BarGroup { // Pomodoro, between the clock and the status indicators.
                // Living in the centered middle group pushed the workspaces
                // off true center whenever the timer was visible.
                id: pomodoroGroup
                Layout.alignment: Qt.AlignVCenter
                // Only while a lap is actually under way. An untouched timer is
                // started from the overflow control instead of sitting here.
                visible: root.useShortenedForm === 0 && pomodoro.inSession

                Pomodoro {
                    id: pomodoro
                    Layout.fillHeight: true
                }
            }

            RippleButton { // Right sidebar button
                id: rightSidebarButton

                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.fillWidth: false

                implicitWidth: indicatorsRowLayout.implicitWidth + Appearance.spacing.small * 2
                implicitHeight: indicatorsRowLayout.implicitHeight + Appearance.spacing.small * 2

                buttonRadius: Appearance.rounding.full
                colBackground: barRightSideMouseArea.hovered ? Appearance.colors.colLayer1Hover : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                colRippleToggled: Appearance.colors.colSecondaryContainerActive
                toggled: GlobalStates.sidebarRightOpen
                property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0

                Behavior on colText {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                onPressed: {
                    GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
                }

                RowLayout {
                    id: indicatorsRowLayout
                    anchors.centerIn: parent
                    property real realSpacing: Appearance.spacing.large
                    spacing: 0

                    // A recording is invisible once its start notification is
                    // gone, and the region it captures may be off-screen, so the
                    // bar carries the light for as long as it runs.
                    Revealer {
                        reveal: ScreenRecording.active
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "screen_record"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.m3colors.m3error
                            // A light that does not move reads as an icon.
                            SequentialAnimation on opacity {
                                running: ScreenRecording.active
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                    Revealer {
                        reveal: Audio.sink?.audio?.muted ?? false
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "volume_off"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rightSidebarButton.colText
                        }
                    }
                    Revealer {
                        reveal: Audio.source?.audio?.muted ?? false
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        MaterialSymbol {
                            text: "mic_off"
                            iconSize: Appearance.font.pixelSize.larger
                            color: rightSidebarButton.colText
                        }
                    }
                    HyprlandXkbIndicator {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: indicatorsRowLayout.realSpacing
                        color: rightSidebarButton.colText
                    }
                    Revealer {
                        reveal: Notifications.silent || Notifications.unread > 0
                        Layout.fillHeight: true
                        Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
                        implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
                        implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
                        Behavior on Layout.rightMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        NotificationUnreadCount {
                            id: notificationUnreadCount
                        }
                    }
                    MaterialSymbol {
                        text: Network.materialSymbol
                        fill: Network.connected ? 1 : 0
                        iconSize: Appearance.font.pixelSize.larger
                        color: rightSidebarButton.colText
                        MouseArea {
                            id: networkHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                        PopupToolTip {
                            extraVisibleCondition: networkHover.containsMouse
                            anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
                            text: Network.networkName !== "" ? Network.networkName : Translation.tr("Network")
                        }
                    }
                }
            }

            BatteryIndicator {
                visible: (root.useShortenedForm < 2 && Battery.available)
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 4
            }

            SysTray {
                visible: root.useShortenedForm === 0
                Layout.fillWidth: false
                Layout.fillHeight: true
                invertSide: Config?.options.bar.bottom
            }

            BarGroup { // One overflow control in place of the utility, weather and media slots
                visible: root.useShortenedForm === 0
                Layout.alignment: Qt.AlignVCenter
                BarOverflow {
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            Item { // Leftmost in RTL: absorbs slack so the cluster pins to the right edge
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
