/*
 * KOOMPI OS – SDDM Login Theme
 * Minimal dark theme inspired by silentSDDM and KDE Breeze
 * Qt 6 / QQC2 – no external component dependencies
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Qt5Compat.GraphicalEffects

Item {
    id: root
    width:  1920
    height: 1080

    // ── Palette ──────────────────────────────────────────────────────────
    readonly property color accent:      "#5294e2"
    readonly property color textPrimary: "#ffffff"
    readonly property color textMuted:   Qt.rgba(1, 1, 1, 0.45)
    readonly property color inputBg:     Qt.rgba(1, 1, 1, 0.05)
    readonly property color inputBorder: Qt.rgba(1, 1, 1, 0.10)
    readonly property color cardBg:      Qt.rgba(0.06, 0.06, 0.06, 0.96)
    readonly property color cardBorder:  Qt.rgba(1, 1, 1, 0.07)

    // ── State ────────────────────────────────────────────────────────────
    property var    now:                 new Date()
    property string notificationMessage: ""
    property bool   showUsernameField:   userModel.count > 1 || userModel.lastUser === ""

    // ── Clock timer ──────────────────────────────────────────────────────
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.now = new Date()
    }

    // ── Login ─────────────────────────────────────────────────────────────
    function doLogin() {
        root.notificationMessage = ""
        const user = root.showUsernameField ? usernameField.text : userModel.lastUser
        sddm.login(user, passwordField.text, sessionCombo.currentIndex)
    }

    // ── SDDM connections ─────────────────────────────────────────────────
    Connections {
        target: sddm
        function onLoginFailed() {
            root.notificationMessage = "Incorrect password – try again"
            passwordField.selectAll()
            passwordField.forceActiveFocus()
            shakeAnim.start()
        }
        function onLoginSucceeded() {
            fadeAnim.start()
        }
    }

    // ── Background ────────────────────────────────────────────────────────
    // A random image out of backgroundDir on every greeter start, blurred and
    // dimmed so the card stays readable over a bright one. The single
    // `background` key is the fallback for when the folder is gone or empty,
    // and the flat colour is the fallback for when that is gone too - the
    // previous theme had only the flat colour left once its wallpaper path
    // stopped existing, which is what made the login screen pure black.
    readonly property real bgBlur: parseFloat(config.blur) || 0.62
    readonly property real bgDim:  parseFloat(config.dim)  || 0.34

    property string chosenWallpaper: ""
    property bool   folderScanned:   false

    Rectangle {
        anchors.fill: parent
        color: config.color || "#0d0d0d"
    }

    FolderListModel {
        id: wallpaperFolder
        folder: config.backgroundDir ? "file://" + config.backgroundDir : ""
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
        showDirs: false
        showHidden: false
        onStatusChanged: {
            if (status !== FolderListModel.Ready)
                return
            if (count > 0)
                root.chosenWallpaper = get(Math.floor(Math.random() * count), "fileUrl")
            root.folderScanned = true
        }
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        // Blurring a downscaled copy is indistinguishable from blurring the
        // full-resolution frame and costs a fraction of the memory.
        sourceSize.height: 1080
        visible: false
        source: root.chosenWallpaper !== "" ? root.chosenWallpaper
              : root.folderScanned          ? (config.background || "")
              : ""
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: wallpaper.status === Image.Ready
        blurEnabled: root.bgBlur > 0
        blur: root.bgBlur
        blurMax: 96
        autoPaddingEnabled: false
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.bgDim
        visible: wallpaper.status === Image.Ready
    }

    // ── Clock (above card) ───────────────────────────────────────────────
    ColumnLayout {
        id: clockBlock
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: loginCard.top
            bottomMargin: 32
        }
        spacing: 4

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(root.now, "hh:mm")
            font { pixelSize: 72; weight: Font.Thin }
            color: root.textPrimary
            renderType: Text.NativeRendering
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            font { pixelSize: 15; weight: Font.Light }
            color: root.textMuted
            renderType: Text.NativeRendering
        }
    }

    // ── Login card ───────────────────────────────────────────────────────
    Rectangle {
        id: loginCard
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 36    // shift slightly below true center
        width: 360
        height: cardLayout.implicitHeight + 64
        radius: 20
        color: root.cardBg
        border { color: root.cardBorder; width: 1 }

        // Glass blur – blurs whatever is behind the card
        layer.enabled: true
        layer.effect: DropShadow {
            color:          Qt.rgba(0, 0, 0, 0.55)
            radius:         36
            samples:        73
            verticalOffset: 14
            spread:         0
        }

        // ── Shake animation on wrong password ────────────────────────────
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target: loginCard; property: "anchors.horizontalCenterOffset"; to: -18; duration: 48; easing.type: Easing.OutQuad }
            NumberAnimation { target: loginCard; property: "anchors.horizontalCenterOffset"; to:  18; duration: 48; easing.type: Easing.InOutQuad }
            NumberAnimation { target: loginCard; property: "anchors.horizontalCenterOffset"; to: -10; duration: 48; easing.type: Easing.InOutQuad }
            NumberAnimation { target: loginCard; property: "anchors.horizontalCenterOffset"; to:  10; duration: 48; easing.type: Easing.InOutQuad }
            NumberAnimation { target: loginCard; property: "anchors.horizontalCenterOffset"; to:   0; duration: 48; easing.type: Easing.OutBounce }
        }

        ColumnLayout {
            id: cardLayout
            anchors {
                top:    parent.top
                left:   parent.left
                right:  parent.right
                margins:   32
                topMargin: 40
            }
            spacing: 14

            // Logo
            Image {
                Layout.alignment: Qt.AlignHCenter
                source: config.logo || ""
                width:  60; height: 60
                fillMode:   Image.PreserveAspectFit
                sourceSize: Qt.size(120, 120)
                smooth: true
                asynchronous: true
            }

            // Hostname
            Text {
                Layout.alignment: Qt.AlignHCenter
                text:  sddm.hostName.toUpperCase()
                font { pixelSize: 11; weight: Font.Medium; letterSpacing: 3 }
                color: root.textMuted
                renderType: Text.NativeRendering
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }

            Item { Layout.preferredHeight: 2 }

            // Username field (only when multiple users or unknown user)
            QQC2.TextField {
                id: usernameField
                Layout.fillWidth: true
                visible: root.showUsernameField
                height:  44
                text: userModel.lastUser
                placeholderText: "Username"
                color: root.textPrimary
                placeholderTextColor: root.textMuted
                font.pixelSize: 14
                leftPadding: 16; rightPadding: 16
                background: Rectangle {
                    radius: 10
                    color:  root.inputBg
                    border.color: usernameField.activeFocus ? root.accent : root.inputBorder
                    border.width: usernameField.activeFocus ? 2 : 1
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                }
                KeyNavigation.down: passwordField
                Keys.onReturnPressed: passwordField.forceActiveFocus()
                Keys.onTabPressed:   passwordField.forceActiveFocus()
            }

            // Password row: field + arrow button
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                QQC2.TextField {
                    id: passwordField
                    Layout.fillWidth: true
                    height: 44
                    echoMode: TextInput.Password
                    placeholderText: "Password"
                    color: root.textPrimary
                    placeholderTextColor: root.textMuted
                    font.pixelSize: 14
                    leftPadding: 16; rightPadding: 16
                    background: Rectangle {
                        radius: 10
                        color:  root.inputBg
                        border.color: passwordField.activeFocus ? root.accent : root.inputBorder
                        border.width: passwordField.activeFocus ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                    }
                    Keys.onReturnPressed: root.doLogin()
                }

                // → Login button
                Rectangle {
                    id: loginBtn
                    width: 44; height: 44; radius: 10
                    color: loginMA.pressed       ? Qt.darker(root.accent, 1.25)
                         : loginMA.containsMouse ? Qt.lighter(root.accent, 1.12)
                         : root.accent
                    Behavior on color { ColorAnimation { duration: 110 } }

                    Text {
                        anchors.centerIn: parent
                        text: "→"
                        font.pixelSize: 20
                        color: "#ffffff"
                    }
                    MouseArea {
                        id: loginMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: root.doLogin()
                    }
                }
            }

            // Error / notification message
            Text {
                Layout.fillWidth: true
                text: root.notificationMessage
                color: "#ff6b6b"
                font { pixelSize: 12; weight: Font.Light }
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: text.length > 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }

    // ── Footer ────────────────────────────────────────────────────────────
    RowLayout {
        id: footer
        anchors {
            bottom: parent.bottom
            left:   parent.left
            right:  parent.right
            margins: 20
        }
        spacing: 6

        // Session selector
        QQC2.ComboBox {
            id: sessionCombo
            model: sessionModel
            currentIndex: sessionModel.lastIndex
            textRole: "name"
            font.pixelSize: 13

            background: Rectangle {
                radius: 8
                color: sessionCombo.hovered ? Qt.rgba(1,1,1,0.07) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            contentItem: Text {
                text: sessionCombo.displayText
                color: root.textMuted
                font: sessionCombo.font
                verticalAlignment: Text.AlignVCenter
                leftPadding: 8
            }
            indicator: Text {
                text: "▾"
                color: root.textMuted
                font.pixelSize: 10
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            }
            popup: QQC2.Popup {
                y: -(height + 4)
                width: Math.max(sessionCombo.width, 180)
                padding: 4
                background: Rectangle {
                    radius: 10
                    color: "#161616"
                    border.color: root.cardBorder
                }
                contentItem: ListView {
                    implicitHeight: contentHeight
                    model: sessionCombo.delegateModel
                    clip: true
                }
            }
            delegate: QQC2.ItemDelegate {
                width: sessionCombo.popup.width
                height: 36
                background: Rectangle {
                    radius: 6
                    color: hovered ? Qt.rgba(1,1,1,0.07) : "transparent"
                }
                contentItem: Text {
                    text: model.name
                    color: root.textPrimary
                    font.pixelSize: 13
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 8
                }
            }
        }

        Item { Layout.fillWidth: true }

        // Power buttons
        Repeater {
            model: ListModel {
                ListElement { label: "↺"; tip: "Restart" }
                ListElement { label: "⏻"; tip: "Shut Down" }
            }
            delegate: Rectangle {
                width: 34; height: 34; radius: 8
                color: pMA.containsMouse ? Qt.rgba(1,1,1,0.09) : "transparent"
                Behavior on color { ColorAnimation { duration: 110 } }
                Text {
                    anchors.centerIn: parent
                    text: model.label
                    font.pixelSize: 15
                    color: root.textMuted
                }
                MouseArea {
                    id: pMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: model.index === 0 ? sddm.reboot() : sddm.powerOff()
                }
                QQC2.ToolTip {
                    visible: pMA.containsMouse
                    text: model.tip
                    font.pixelSize: 12
                    delay: 400
                }
            }
        }
    }

    // ── Fade out on success ───────────────────────────────────────────────
    PropertyAnimation {
        id: fadeAnim
        target: root; property: "opacity"; to: 0
        duration: 400; easing.type: Easing.InOutQuad
    }

    // ── Fade in on load ───────────────────────────────────────────────────
    NumberAnimation on opacity {
        from: 0; to: 1
        duration: 500; easing.type: Easing.OutCubic
        running: true
    }

    // ── Initial focus ────────────────────────────────────────────────────
    Component.onCompleted: {
        if (root.showUsernameField)
            usernameField.forceActiveFocus()
        else
            passwordField.forceActiveFocus()
    }
}
