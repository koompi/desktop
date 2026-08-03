pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.modules.koompi.bar as Bar
import Quickshell
import Quickshell.Services.SystemTray

/**
 * Everything the user sees while the session is locked.
 *
 * This is the only place the lock wallpaper is drawn. The desktop background
 * panel sits on WlrLayer.Bottom and is hidden by the compositor for the whole
 * time the session lock is up, so it contributes nothing here and pays for no
 * lock-only effects.
 */
MouseArea {
    id: root
    required property LockContext context

    // Set by the Loader in LockScreen. Empty only if this is ever instantiated
    // outside one, in which case the context falls back to a live lookup.
    readonly property string screenName: parent?.lockScreenName ?? ""
    // The password has been accepted and this surface is on its way out. Set by
    // the Loader in LockScreen, which keeps the surface alive until the exit has
    // played. Everything that is lock furniture leaves; the wallpaper does not,
    // and loses its blur, veil and zoom so the last frame here is as close as it
    // can get to the first frame of the desktop.
    readonly property bool unlocking: parent?.lockUnlocking ?? false
    readonly property int exitDuration: parent?.lockExitDuration ?? 350
    readonly property string wallpaperPath: root.context.wallpaperForScreen(root.screenName)

    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower

    // Responsive metrics
    // Everything here is in logical pixels, so fractional scaling is already
    // applied by the compositor and needs no separate handling.
    readonly property bool compact: root.width < 1000
    readonly property int edgeMargin: root.compact ? 12 : 20
    // Islands stack only once compacting them is not enough. Their implicit
    // widths depend on `compact`, which depends on root.width alone, so this
    // cannot feed back into itself.
    readonly property bool stackIslands: root.width < (leftIsland.implicitWidth + mainIsland.implicitWidth + rightIsland.implicitWidth + islandGrid.spacing * 2 + root.edgeMargin * 2)

    // Wallpaper treatment
    // A bright photo needs a heavier veil than a dark one for the same text to
    // read, and two screens on two workspaces can need two different veils.
    readonly property real scrimOpacity: Math.max(0.22, Math.min(0.66, 0.22 + root.context.luminanceForScreen(root.screenName) * 0.45))
    // The scrim is always a dark veil, so anything drawn on it is light. Tinted
    // with the theme accent so the lock screen still belongs to the palette.
    readonly property color colOnScrim: ColorUtils.mix("#FFFFFF", Appearance.colors.colPrimary, 0.85)

    // Hold the content back until there is something behind it, so the first
    // frame is never a bare colour that then jumps to a photo. The timer is the
    // escape hatch for a slow disk or a wallpaper that never resolves.
    property bool wallpaperSettled: false
    readonly property bool contentReady: root.wallpaperSettled || lockWallpaper.status === Image.Ready
    Timer {
        id: wallpaperGraceTimer
        interval: 400
        onTriggered: root.wallpaperSettled = true
    }

    // Focus
    function forceFieldFocus() {
        passwordBox.forceActiveFocus();
    }
    Connections {
        target: root.context
        function onShouldReFocus() {
            root.forceFieldFocus();
        }
    }
    // Hyprland drops keyboard focus on resume and on monitor hot-plug, and
    // there is no event for either that reaches this surface. A cheap poll is
    // more reliable than trying to catch every cause.
    Timer {
        interval: 1000
        repeat: true
        running: GlobalStates.screenLocked
        onTriggered: {
            if (!passwordBox.activeFocus) root.forceFieldFocus();
        }
    }

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => {
        root.forceFieldFocus();
    }
    onPositionChanged: mouse => {
        root.forceFieldFocus();
    }

    // Entrance and exit of everything that is not the wallpaper. One duration
    // and one curve for every part of it, in both directions: a fade that ends
    // before the thing it was fading has finished moving is most of what reads
    // as rough here, and the only way to be sure that never happens is to have
    // a single answer for how long a change takes.
    readonly property bool furnitureShown: root.contentReady && !root.unlocking
    component LockAnimation: NumberAnimation {
        duration: root.unlocking ? root.exitDuration : Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasized
    }

    property real toolbarScale: root.furnitureShown ? 1 : 0.94
    property real toolbarOpacity: root.furnitureShown ? 1 : 0
    Behavior on toolbarScale {
        LockAnimation {}
    }
    Behavior on toolbarOpacity {
        LockAnimation {}
    }

    Component.onCompleted: {
        forceFieldFocus();
        wallpaperGraceTimer.restart();
    }

    // Keys
    property bool ctrlHeld: false
    Keys.onPressed: event => {
        root.context.resetClearTimer();
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = true;
        }
        if (event.key === Qt.Key_Escape) { // Esc to clear
            root.context.currentText = "";
            root.disarm();
        }
        if (event.key === Qt.Key_CapsLock) {
            capsLockRefreshTimer.restart();
        }
        forceFieldFocus();
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Control) {
            root.ctrlHeld = false;
        }
        if (event.key === Qt.Key_CapsLock) {
            capsLockRefreshTimer.restart();
        }
        forceFieldFocus();
    }
    // Hyprland applies the modifier after it forwards the key, so read it back
    // a frame later rather than on the event itself.
    Timer {
        id: capsLockRefreshTimer
        interval: 60
        onTriggered: root.context.refreshCapsLock()
    }

    // Background: base colour, wallpaper, blur, scrim. Drawn once, here.
    Rectangle {
        anchors.fill: parent
        color: Appearance.m3colors.m3background
        z: -4
    }

    Image {
        id: lockWallpaper
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        // Shared across monitors, so let the pixmap cache serve the second
        // screen and every subsequent lock from the first decode.
        cache: true
        // Blurring a downscaled copy is indistinguishable from blurring the
        // full-resolution frame and costs a fraction of the memory. Without
        // blur the image is shown as-is, so it has to stay sharp.
        sourceSize.height: Config.options.lock.blur.enable ? Math.min(1080, root.height) : 0
        source: root.wallpaperPath.length > 0 ? `file://${root.wallpaperPath}` : ""

        // No fade in. This is the same photo the desktop was already showing, so
        // fading it up from the base colour is a flash of theme background over
        // a wallpaper that never actually went away.
        // While unlocking it is uncovered from under the blurred copy fading out
        // above it. Two copies of one photo for a third of a second is cheaper
        // than animating the blur radius, which re-runs every blur pass on every
        // frame and stutters on an integrated GPU at exactly the moment this is
        // trying to look smooth.
        visible: status === Image.Ready && (!blurLoader.active || root.unlocking)

        scale: root.wallpaperScale
        z: -3
    }

    // A slight settle on entry, from the configured zoom and a touch more, and
    // all the way back on exit: the desktop underneath draws this same photo
    // with no zoom of its own.
    property real wallpaperScale: {
        if (root.unlocking)
            return 1;
        return Config.options.lock.blur.extraZoom * (root.contentReady ? 1 : 1.04);
    }
    Behavior on wallpaperScale {
        LockAnimation {}
    }

    Loader {
        id: blurLoader
        anchors.fill: parent
        // The blur exists only while there is a decoded frame to blur, so
        // nothing is allocated on the GPU before or after that.
        active: Config.options.lock.blur.enable && lockWallpaper.status === Image.Ready
        visible: active
        z: -3
        sourceComponent: MultiEffect {
            source: lockWallpaper
            blurEnabled: true
            // Never animated, only faded. See the note on lockWallpaper.visible.
            blur: 1.0
            // A separable multi-pass blur, unlike the single-pass GaussianBlur
            // this replaced, which needed samples: radius * 2 + 1 (201 samples
            // at the default radius) for the same look. Past a 64 px kernel the
            // result is indistinguishable, so the configured radius is clamped
            // rather than obeyed literally.
            blurMax: Math.round(Math.max(8, Math.min(64, Config.options.lock.blur.radius)))
            autoPaddingEnabled: false
            scale: root.wallpaperScale
            opacity: root.furnitureShown ? 1 : 0
            Behavior on opacity {
                LockAnimation {}
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        // The veil exists to make lock text readable. Once the text is leaving
        // there is nothing to make readable, and the desktop is not veiled.
        opacity: (lockWallpaper.status === Image.Ready && !root.unlocking) ? root.scrimOpacity : 0
        Behavior on opacity {
            LockAnimation {}
        }
        z: -2
    }

    // Clock, date and lock indicator
    Item {
        id: clockArea
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: bottomStack.top
            bottomMargin: root.edgeMargin
        }
        opacity: root.furnitureShown ? 1 : 0
        visible: opacity > 0
        // The clock is the largest thing on screen, so it is the one whose
        // timing is most obvious if it disagrees with anything else.
        Behavior on opacity {
            LockAnimation {}
        }
        scale: root.furnitureShown ? 1 : 0.98
        Behavior on scale {
            LockAnimation {}
        }

        LockClock {
            id: lockClock
            colText: root.colOnScrim
            anchors.horizontalCenter: parent.horizontalCenter
            // Centred in whatever room the islands leave, so the two can never
            // overlap however short the screen is.
            y: Config.options.lock.centerClock
                ? (parent.height - height) / 2
                : Math.max(root.edgeMargin, parent.height * 0.15)
            transformOrigin: Item.Center
            // A portrait or 720p panel does not have room for a clock sized for
            // a desktop. Shrink rather than clip.
            scale: {
                if (implicitWidth <= 0 || implicitHeight <= 0) return 1;
                const availableWidth = Math.max(1, clockArea.width - root.edgeMargin * 4);
                const availableHeight = Math.max(1, clockArea.height - root.edgeMargin * 2);
                return Math.max(0.45, Math.min(1, availableWidth / implicitWidth, availableHeight / implicitHeight));
            }
            Behavior on scale {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
        }
    }

    // Status messages and authentication islands
    ColumnLayout {
        id: bottomStack
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: root.edgeMargin
        }
        width: Math.min(root.width - root.edgeMargin * 2, implicitWidth)
        spacing: 10

        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6
            opacity: root.toolbarOpacity

            StatusPill {
                shown: root.context.capsLockOn
                icon: "keyboard_capslock"
                text: Translation.tr("Caps Lock is on")
                colBackground: Appearance.colors.colSecondaryContainer
                colContent: Appearance.colors.colOnSecondaryContainer
            }
            StatusPill {
                shown: root.confirmMessage.length > 0
                icon: "warning"
                text: root.confirmMessage
                colBackground: Appearance.colors.colErrorContainer
                colContent: Appearance.colors.colOnErrorContainer
            }
            StatusPill {
                shown: root.context.failureMessage.length > 0
                icon: "error"
                text: root.context.failureMessage
                colBackground: Appearance.colors.colErrorContainer
                colContent: Appearance.colors.colOnErrorContainer
            }
            StatusPill {
                shown: root.context.fingerprintMessage.length > 0
                icon: "fingerprint"
                text: root.context.fingerprintMessage
                colBackground: Appearance.colors.colSurfaceContainer
                colContent: Appearance.colors.colOnSurfaceVariant
            }
        }

        Grid {
            id: islandGrid
            Layout.alignment: Qt.AlignHCenter
            columns: root.stackIslands ? 1 : 3
            spacing: 10
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            // Left island: who is logged in, and what the keyboard will type
            Toolbar {
                id: leftIsland
                implicitHeight: mainIsland.implicitHeight
                scale: root.toolbarScale
                opacity: root.toolbarOpacity

                IconAndTextPair {
                    Layout.leftMargin: 8
                    icon: "account_circle"
                    // The username is a label, not a secret, but there is no
                    // reason to spend scarce width on it.
                    text: root.compact ? "" : SystemInfo.username
                }

                Row {
                    Layout.rightMargin: 8
                    Layout.fillHeight: true
                    spacing: 8

                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        fill: 1
                        text: "keyboard_alt"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.compact
                        text: HyprlandXkb.currentLayoutCode
                        color: Appearance.colors.colOnSurfaceVariant
                        animateChange: true
                    }
                }

                // Keyboard layout (Fcitx)
                Bar.SysTray {
                    Layout.rightMargin: 10
                    Layout.alignment: Qt.AlignVCenter
                    showSeparator: false
                    pinnedItems: SystemTray.items.values.filter(i => i.id == "Fcitx")
                    unpinnedItems: []
                    visible: pinnedItems.length > 0
                }
            }

            // Main island: the password field
            Toolbar {
                id: mainIsland
                scale: root.toolbarScale
                opacity: root.toolbarOpacity

                Loader {
                    Layout.leftMargin: 10
                    Layout.rightMargin: 6
                    Layout.alignment: Qt.AlignVCenter
                    active: root.context.fingerprintsConfigured
                    visible: active

                    sourceComponent: MaterialSymbol {
                        id: fingerprintIcon
                        fill: 1
                        text: "fingerprint"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: {
                            switch (root.context.fingerprintState) {
                            case LockContext.FingerprintEnum.Scanning:
                                return Appearance.colors.colPrimary;
                            case LockContext.FingerprintEnum.Failed:
                                return Appearance.colors.colError;
                            case LockContext.FingerprintEnum.Error:
                                return Appearance.colors.colSubtext;
                            default:
                                return Appearance.colors.colOnSurfaceVariant;
                            }
                        }
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                        // A reader that is actually sampling says so.
                        SequentialAnimation on opacity {
                            running: root.context.fingerprintState === LockContext.FingerprintEnum.Scanning
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation {
                                to: 0.45
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: 1
                                duration: Appearance.animation.elementMove.duration
                                easing.type: Easing.InOutSine
                            }
                        }
                    }
                }

                ToolbarTextField {
                    id: passwordBox
                    Layout.rightMargin: -Layout.leftMargin
                    implicitWidth: root.compact ? 150 : 200
                    placeholderText: Translation.tr("Enter password")
                    Accessible.role: Accessible.EditableText
                    Accessible.name: Translation.tr("Password")
                    Accessible.description: root.context.failureMessage.length > 0
                        ? root.context.failureMessage
                        : Translation.tr("Enter your password to unlock")

                    // Style
                    clip: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
                    selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

                    // Password
                    enabled: !root.context.unlockInProgress
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData

                    // Synchronizing (across monitors) and unlocking
                    onTextChanged: root.context.currentText = this.text
                    onAccepted: {
                        root.context.tryUnlock(root.ctrlHeld);
                    }
                    Connections {
                        target: root.context
                        function onCurrentTextChanged() {
                            passwordBox.text = root.context.currentText;
                        }
                    }

                    Keys.onPressed: event => {
                        root.context.resetClearTimer();
                    }

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: passwordBox.width - 8
                            height: passwordBox.height
                            radius: height / 2
                        }
                    }

                    // Shake when wrong password. The textual error in the status
                    // strip carries the same information for anyone who cannot
                    // see or does not notice the motion.
                    ErrorShakeAnimation {
                        id: wrongPasswordShakeAnim
                        target: passwordBox
                    }
                    Connections {
                        target: GlobalStates
                        function onScreenUnlockFailedChanged() {
                            if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
                        }
                    }

                    // We're drawing dots manually
                    property bool materialShapeChars: Config.options.lock.materialShapeChars
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
                    Loader {
                        active: passwordBox.materialShapeChars
                        anchors {
                            fill: parent
                            leftMargin: passwordBox.padding
                            rightMargin: passwordBox.padding
                        }
                        sourceComponent: PasswordChars {
                            length: root.context.currentText.length
                            selectionStart: passwordBox.selectionStart
                            selectionEnd: passwordBox.selectionEnd
                            cursorPosition: passwordBox.cursorPosition
                        }
                    }
                }

                ToolbarButton {
                    id: confirmButton
                    implicitWidth: height
                    toggled: true
                    enabled: !root.context.unlockInProgress
                    colBackgroundToggled: Appearance.colors.colPrimary
                    Accessible.name: Translation.tr("Unlock")

                    onClicked: root.context.tryUnlock()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 24
                        text: {
                            if (root.context.targetAction === LockContext.ActionEnum.Poweroff) {
                                return "power_settings_new";
                            } else if (root.context.targetAction === LockContext.ActionEnum.Reboot) {
                                return "restart_alt";
                            }
                            return root.ctrlHeld ? "coffee" : "arrow_right_alt";
                        }
                        color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                    }
                }
            }

            // Right island: battery and session actions
            Toolbar {
                id: rightIsland
                implicitHeight: mainIsland.implicitHeight
                scale: root.toolbarScale
                opacity: root.toolbarOpacity

                IconAndTextPair {
                    visible: Battery.available
                    icon: Battery.isCharging ? "bolt" : "battery_android_full"
                    text: Math.round(Battery.percentage * 100)
                    color: (Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                }

                SessionActionButton {
                    id: sleepButton
                    text: "dark_mode"
                    actionName: Translation.tr("suspend")
                    accessibleName: Translation.tr("Suspend")
                    // Suspending is recoverable, so it never asks for the
                    // password; the second press is guard enough.
                    passwordAction: undefined
                    onExecute: Session.suspend()
                }

                SessionActionButton {
                    id: powerButton
                    text: "power_settings_new"
                    actionName: Translation.tr("shut down")
                    accessibleName: Translation.tr("Shut down")
                    passwordAction: LockContext.ActionEnum.Poweroff
                    onExecute: root.context.unlocked(LockContext.ActionEnum.Poweroff)
                }

                SessionActionButton {
                    id: rebootButton
                    text: "restart_alt"
                    actionName: Translation.tr("restart")
                    accessibleName: Translation.tr("Restart")
                    passwordAction: LockContext.ActionEnum.Reboot
                    onExecute: root.context.unlocked(LockContext.ActionEnum.Reboot)
                }
            }
        }
    }

    // Session actions
    // Nothing on the session row fires on a single press. Either the action is
    // behind the password (requirePasswordToPower), or it needs a second,
    // deliberate press within a few seconds.
    property var armedButton: null
    property string confirmMessage: ""

    function armButton(button, message) {
        root.armedButton = button;
        root.confirmMessage = message;
        disarmTimer.restart();
    }
    function disarm() {
        root.armedButton = null;
        root.confirmMessage = "";
        disarmTimer.stop();
    }
    Timer {
        id: disarmTimer
        interval: 5000
        onTriggered: root.disarm()
    }
    Connections {
        target: root.context
        function onTargetActionChanged() {
            if (root.context.targetAction === LockContext.ActionEnum.Unlock) root.disarm();
        }
    }

    component SessionActionButton: IconToolbarButton {
        id: sessionBtn
        // LockContext.ActionEnum member, or undefined when the action cannot be
        // handed to PAM.
        property var passwordAction: undefined
        required property string actionName
        required property string accessibleName
        signal execute()

        readonly property bool guardedByPassword: sessionBtn.passwordAction !== undefined && root.requirePasswordToPower
        readonly property bool armed: root.armedButton === sessionBtn

        Accessible.name: sessionBtn.accessibleName
        toggled: sessionBtn.armed || (sessionBtn.guardedByPassword && root.context.targetAction === sessionBtn.passwordAction)
        colBackgroundToggled: sessionBtn.armed ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
        colText: sessionBtn.armed ? Appearance.colors.colOnErrorContainer : (toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant)

        onClicked: {
            if (sessionBtn.guardedByPassword) {
                if (root.context.targetAction === sessionBtn.passwordAction) {
                    root.context.resetTargetAction();
                } else {
                    root.context.targetAction = sessionBtn.passwordAction;
                    root.context.shouldReFocus();
                }
                return;
            }
            if (sessionBtn.armed) {
                root.disarm();
                sessionBtn.execute();
                return;
            }
            root.armButton(sessionBtn, Translation.tr("Press again to %1").arg(sessionBtn.actionName));
            root.context.shouldReFocus();
        }
    }

    component StatusPill: Item {
        id: pill
        required property string icon
        required property string text
        property bool shown: true
        property color colBackground: Appearance.colors.colSurfaceContainer
        property color colContent: Appearance.colors.colOnSurfaceVariant

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: pillBackground.implicitWidth
        implicitHeight: pill.shown ? pillBackground.implicitHeight : 0
        opacity: pill.shown ? 1 : 0
        visible: opacity > 0
        Accessible.role: Accessible.StaticText
        Accessible.name: pill.text

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        Rectangle {
            id: pillBackground
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: pillRow.implicitWidth + 14 * 2
            implicitHeight: pillRow.implicitHeight + 6 * 2
            radius: height / 2
            color: pill.colBackground

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: pill.icon
                    fill: 1
                    iconSize: Appearance.font.pixelSize.large
                    color: pill.colContent
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: pill.text
                    color: pill.colContent
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }

    component IconAndTextPair: Row {
        id: pair
        required property string icon
        required property string text
        property color color: Appearance.colors.colOnSurfaceVariant

        spacing: 4
        Layout.fillHeight: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            fill: 1
            text: pair.icon
            iconSize: Appearance.font.pixelSize.huge
            animateChange: true
            color: pair.color
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: pair.text.length > 0
            text: pair.text
            color: pair.color
        }
    }
}
