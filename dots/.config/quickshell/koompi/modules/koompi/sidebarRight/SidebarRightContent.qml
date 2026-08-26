import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

import qs.modules.koompi.bar
import qs.modules.koompi.bar.weather
import qs.modules.koompi.mediaControls
import qs.modules.koompi.sidebarRight.quickToggles
import qs.modules.koompi.sidebarRight.quickToggles.classicStyle

import qs.modules.koompi.sidebarRight.bluetoothDevices
import qs.modules.koompi.sidebarRight.calendar
import qs.modules.koompi.sidebarRight.nightLight
import qs.modules.koompi.sidebarRight.notifications
import qs.modules.koompi.sidebarRight.pomodoro
import qs.modules.koompi.sidebarRight.todo
import qs.modules.koompi.sidebarRight.volumeMixer
import qs.modules.koompi.sidebarRight.wifiNetworks

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidthRight
    property int sidebarPadding: Appearance.spacing.normal
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false
    property string drawer: ""
    // Survives the slide-out so the drawer keeps its content while closing.
    property string drawerPage: ""
    onDrawerChanged: if (drawer.length > 0) drawerPage = drawer

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
                root.drawer = "";
                root.editMode = false;
            }
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: 1
        // The outline carries the keyboard. `Window.active` is this surface's own
        // focus, not `sidebarRightOpen`: the panel stays on screen when Search
        // opens over it and takes the keys.
        border.color: Window.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            SystemButtonRow {
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.topMargin: Appearance.spacing.small
                Layout.bottomMargin: 0
            }

            Loader {
                Layout.fillWidth: true
                visible: active
                active: {
                    const configQuickSliders = Config.options.sidebar.quickSliders
                    if (!configQuickSliders.enable) return false
                    if (!configQuickSliders.showMic && !configQuickSliders.showVolume && !configQuickSliders.showBrightness) return false;
                    return true;
                }
                sourceComponent: QuickSliders {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            // Three rows only. The rest of the grid lives one drawer deep.
            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    maxRows: 3
                }
            }

            DrawerRow {
                rowIcon: "tune"
                rowText: Translation.tr("All controls")
                onClicked: root.drawer = "controls"
            }

            // The bar's Media widget used to sit here, centred. It is built for a
            // bar: one line, a 150px title cap, no artist, no track buttons. In a
            // 420px panel that read as a label rather than a player, so this is
            // the same card the media popup uses, at the width it was drawn for.
            Loader {
                Layout.fillWidth: true
                active: MprisController.hasActiveMedia
                visible: active
                sourceComponent: PlayerControl {
                    player: MprisController.activePlayer
                    visualizerPoints: Cava.points
                    implicitHeight: Appearance.sizes.mediaControlsHeight
                    radius: Appearance.rounding.normal
                }
            }

            SectionLabel {
                text: Translation.tr("Today")
            }

            Loader {
                Layout.fillWidth: true
                active: Config.options.bar.weather.enable
                visible: active
                sourceComponent: Rectangle {
                    implicitHeight: weatherBar.implicitHeight + Appearance.spacing.small * 2
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    WeatherBar {
                        id: weatherBar
                        anchors.centerIn: parent
                    }
                }
            }

            // Today's meetings, when a calendar is connected. Bound to the clock
            // so it rolls over at midnight instead of pinning to load time.
            Loader {
                Layout.fillWidth: true
                active: GoogleCalendar.connected && GoogleCalendar.eventsOn(DateTime.clock.date).length > 0
                visible: active
                sourceComponent: Rectangle {
                    implicitHeight: todayEvents.implicitHeight + Appearance.spacing.normal * 2
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: todayEvents
                        anchors.fill: parent
                        anchors.margins: Appearance.spacing.normal
                        spacing: Appearance.spacing.small

                        Repeater {
                            model: GoogleCalendar.eventsOn(DateTime.clock.date)
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Appearance.spacing.normal
                                StyledText {
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colPrimary
                                    text: modelData.allDay ? Translation.tr("all day") : modelData.start.toLocaleTimeString(Qt.locale(), "hh:mm")
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                    text: modelData.summary
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.minimumHeight: 120
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1

                NotificationList {
                    anchors.fill: parent
                    anchors.margins: Appearance.spacing.small
                }
            }

            SectionLabel {
                text: Translation.tr("Personal")
            }

            DrawerRow {
                rowIcon: "calendar_month"
                rowText: Translation.tr("Calendar")
                onClicked: root.drawer = "calendar"
            }

            DrawerRow {
                rowIcon: "done_outline"
                rowText: Translation.tr("To Do")
                onClicked: root.drawer = "todo"
            }

            DrawerRow {
                rowIcon: "schedule"
                rowText: Translation.tr("Timer")
                onClicked: root.drawer = "timer"
            }
        }

        SidebarDrawer {
            shown: root.drawer.length > 0
            onDismissed: root.drawer = ""
            title: {
                if (root.drawerPage === "controls") return Translation.tr("All controls");
                if (root.drawerPage === "calendar") return Translation.tr("Calendar");
                if (root.drawerPage === "todo") return Translation.tr("To Do");
                if (root.drawerPage === "timer") return Translation.tr("Timer");
                return "";
            }
            // Every page named, and an unknown one draws nothing. A default branch
            // here silently opened whichever page it named instead.
            sourceComponent: {
                if (root.drawerPage === "controls") return controlsPage;
                if (root.drawerPage === "calendar") return calendarPage;
                if (root.drawerPage === "todo") return todoPage;
                if (root.drawerPage === "timer") return timerPage;
                return null;
            }
        }
    }

    Component {
        id: controlsPage
        ColumnLayout {
            spacing: Appearance.spacing.small

            LoaderedQuickPanelImplementation {
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {}
            }

            LoaderedQuickPanelImplementation {
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                }
            }

            QuickToggleButton {
                Layout.alignment: Qt.AlignRight
                // GroupButton fills its cell unless a ButtonGroup indexes it.
                Layout.fillHeight: false
                Layout.fillWidth: false
                visible: Config.options.sidebar.quickToggles.style === "android"
                toggled: root.editMode
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    Component {
        id: calendarPage
        CalendarWidget {}
    }

    Component {
        id: todoPage
        TodoWidget {}
    }

    Component {
        id: timerPage
        PomodoroWidget {}
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!shown) {
                BluetoothStatus.setDiscovering(false);
            } else {
                BluetoothStatus.setEnabled(true);
                BluetoothStatus.setDiscovering(true);
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString]) toggleDialogLoader.active = false;
            }
        }
    }

    component SectionLabel: StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.spacing.small
        Layout.bottomMargin: -Appearance.spacing.small
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    component DrawerRow: RippleButton {
        id: drawerRow
        property string rowIcon
        property string rowText

        Layout.fillWidth: true
        implicitHeight: 44
        horizontalPadding: Appearance.spacing.normal
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer1

        contentItem: RowLayout {
            spacing: Appearance.spacing.normal
            MaterialSymbol {
                iconSize: 20
                color: Appearance.colors.colOnLayer1
                text: drawerRow.rowIcon
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer1
                text: drawerRow.rowText
            }
            MaterialSymbol {
                iconSize: 20
                color: Appearance.colors.colSubtext
                text: "chevron_right"
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() {
                root.showAudioOutputDialog = true;
            }
            function onOpenAudioInputDialog() {
                root.showAudioInputDialog = true;
            }
            function onOpenBluetoothDialog() {
                root.showBluetoothDialog = true;
            }
            function onOpenNightLightDialog() {
                root.showNightLightDialog = true;
            }
            function onOpenWifiDialog() {
                root.showWifiDialog = true;
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)

        Rectangle {
            id: uptimeContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: Appearance.colors.colLayer1
            radius: height / 2
            implicitWidth: uptimeRow.implicitWidth + 24
            implicitHeight: uptimeRow.implicitHeight + 8
            
            Row {
                id: uptimeRow
                anchors.centerIn: parent
                spacing: Appearance.spacing.normal
                CustomIcon {
                    id: distroIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 25
                    height: 25
                    source: SystemInfo.distroIcon
                    colorize: true
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("Up %1").arg(DateTime.uptime)
                    textFormat: Text.MarkdownText
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: Appearance.spacing.small

            QuickToggleButton {
                toggled: Persistent.states.sidebar.pinned
                buttonIcon: Persistent.states.sidebar.pinned ? "keep" : "keep_off"
                onClicked: Persistent.states.sidebar.pinned = !Persistent.states.sidebar.pinned
                StyledToolTip {
                    text: Translation.tr("Pin the panel open and tile windows beside it")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "restart_alt"
                onClicked: {
                    Quickshell.execDetached(["hyprctl", "reload"])
                    Quickshell.reload(true);
                }
                StyledToolTip {
                    text: Translation.tr("Reload Hyprland & Quickshell")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/koompi-settings"]);
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "power_settings_new"
                onClicked: {
                    GlobalStates.sessionOpen = true;
                }
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
