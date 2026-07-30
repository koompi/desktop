import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pam

Scope {
    id: root

    enum ActionEnum { Unlock, Poweroff, Reboot }
    enum FingerprintEnum { Unavailable, Ready, Scanning, Failed, Error }

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    // These properties are in the context and not individual lock surfaces
    // so all surfaces can share the same state.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool fingerprintsConfigured: false
    property int fingerprintState: LockContext.FingerprintEnum.Unavailable
    property bool capsLockOn: false
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false

    readonly property string failureMessage: root.showFailure ? Translation.tr("Incorrect password. Try again.") : ""
    readonly property string fingerprintMessage: {
        switch (root.fingerprintState) {
        case LockContext.FingerprintEnum.Ready:
            return Translation.tr("Touch the fingerprint reader");
        case LockContext.FingerprintEnum.Scanning:
            return Translation.tr("Reading fingerprint…");
        case LockContext.FingerprintEnum.Failed:
            return Translation.tr("Fingerprint not recognized. Use your password.");
        case LockContext.FingerprintEnum.Error:
            return Translation.tr("Fingerprint reader unavailable. Use your password.");
        default:
            return "";
        }
    }

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    function resetClearTimer() {
        passwordClearTimer.restart();
    }

    function reset() {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
        root.showFailure = false;
        GlobalStates.screenUnlockFailed = false;
        stopFingerPam();
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        onTriggered: {
            root.reset();
        }
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) {
            showFailure = false;
            GlobalStates.screenUnlockFailed = false;
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        passwordClearTimer.restart();
    }

    function tryUnlock(alsoInhibitIdle = false) {
        if (root.unlockInProgress) return;
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.unlockInProgress = true;
        pam.start();
    }

    function tryFingerUnlock() {
        if (root.fingerprintsConfigured) {
            root.fingerprintState = LockContext.FingerprintEnum.Ready;
            fingerPam.start();
        }
    }

    function stopFingerPam() {
        if (fingerPam.active) {
            fingerPam.abort();
        }
        if (root.fingerprintState === LockContext.FingerprintEnum.Scanning) {
            root.fingerprintState = LockContext.FingerprintEnum.Ready;
        }
    }

    // ---------------------------------------------------------------------
    // Caps Lock
    // ---------------------------------------------------------------------
    // Hyprland emits no event for the lock modifiers, so this is polled: once
    // when the screen locks, and again whenever a surface sees the key. That
    // covers every way the state can change while the lock is up.
    function refreshCapsLock() {
        capsLockProc.running = false;
        capsLockProc.running = true;
    }
    Process {
        id: capsLockProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            id: capsLockCollector
            onStreamFinished: {
                if (capsLockCollector.text.length === 0) return;
                try {
                    const keyboards = JSON.parse(capsLockCollector.text).keyboards ?? [];
                    // Any keyboard, not just the one Hyprland calls main: an
                    // external keyboard is often not the main one, and warning
                    // when it is off is far cheaper than staying quiet when it
                    // is on.
                    root.capsLockOn = keyboards.some(k => k.capsLock === true);
                } catch (e) {
                    root.capsLockOn = false;
                }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Wallpaper
    // ---------------------------------------------------------------------
    // The lock owns no wallpaper. Each surface shows whatever its workspace was
    // already showing, blurred, so locking reads as a frosted pane over the
    // desktop rather than as a different machine. Workspaces carry their own
    // wallpapers, so this is per screen and cannot be one shared path.
    //
    // It has to be a snapshot rather than a live binding: the koompi lock moves
    // every monitor to an out-of-range workspace while it is up, and asking
    // after that returns the inherited wallpaper instead of the one that was on
    // screen. captureWallpapers() runs before anything moves.
    property var screenWallpapers: ({})

    function clearCapturedWallpapers() {
        root.screenWallpapers = ({});
    }

    // Only ever answers for a screen it has no answer for yet. A monitor that
    // arrives mid-lock can be captured without re-reading the ones that have
    // already been moved out of the way, which would read back the wrong
    // workspace.
    function captureWallpapers(screens) {
        const captured = Object.assign({}, root.screenWallpapers);
        for (let i = 0; i < screens.length; ++i) {
            const name = screens[i].name;
            if (captured[name] !== undefined)
                continue;
            const workspaceId = Hyprland.monitorFor(screens[i])?.activeWorkspace?.id ?? -1;
            captured[name] = Wallpapers.forWorkspace(workspaceId);
        }
        root.screenWallpapers = captured;
        root.measureLuminance();
    }

    // For a surface nobody captured - a monitor plugged in while locked, or a
    // lock that never moves anything. An unknown workspace inherits.
    function liveWallpaperFor(screenName: string): string {
        const monitor = Hyprland.monitors.values.find(m => m.name === screenName);
        return Wallpapers.forWorkspace(monitor?.activeWorkspace?.id ?? -1);
    }

    function wallpaperForScreen(screenName: string): string {
        return root.screenWallpapers[screenName] ?? root.liveWallpaperFor(screenName);
    }

    // 0 is black, 1 is white. Drives each surface's scrim so a bright photo is
    // dimmed harder than a dark one and the clock reads on both. Keyed by path,
    // because two screens showing two workspaces need two answers, and two
    // screens showing the same one should only be measured once.
    property var wallpaperLuminances: ({})

    function luminanceForScreen(screenName: string): real {
        return root.wallpaperLuminances[root.wallpaperForScreen(screenName)] ?? 0.5;
    }

    function measureLuminance() {
        const paths = Object.values(root.screenWallpapers).filter((path, index, all) => path.length > 0 && all.indexOf(path) === index);
        if (paths.length === 0)
            return;
        luminanceProc.running = false;
        // Paths are passed as arguments rather than spliced into the script, so
        // a quote or a space in a filename cannot break out of it.
        luminanceProc.command = ["sh", "-c", 'for p in "$@"; do printf "%s\\t" "$p"; magick "$p" -resize 1x1\\! -format "%[fx:(r+g+b)/3]" info: 2>/dev/null; echo; done', "sh"].concat(paths);
        luminanceProc.running = true;
    }

    Process {
        id: luminanceProc
        stdout: StdioCollector {
            id: luminanceCollector
            onStreamFinished: {
                const measured = ({});
                for (const line of luminanceCollector.text.split("\n")) {
                    const parts = line.split("\t");
                    if (parts.length < 2)
                        continue;
                    const luminance = parseFloat(parts[1].trim());
                    // No ImageMagick, or an image it cannot measure: the middle
                    // of the range gives the scrim its neutral value.
                    measured[parts[0]] = isNaN(luminance) ? 0.5 : Math.max(0, Math.min(1, luminance));
                }
                root.wallpaperLuminances = measured;
            }
        }
    }

    Process {
        id: fingerprintCheckProc
        running: true
        command: ["bash", "-c", "fprintd-list $(whoami)"]
        stdout: StdioCollector {
            id: fingerprintOutputCollector
            onStreamFinished: {
                root.fingerprintsConfigured = fingerprintOutputCollector.text.includes("Fingerprints for user");
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.fingerprintsConfigured = false;
            }
        }
    }

    onFingerprintsConfiguredChanged: {
        if (!root.fingerprintsConfigured) root.fingerprintState = LockContext.FingerprintEnum.Unavailable;
    }

    PamContext {
        id: pam

        // pam_unix will ask for a response for the password prompt
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.currentText);
            }
        }

        // pam_unix won't send any important messages so all we need is the completion status.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                GlobalStates.screenUnlockFailed = true;
                root.showFailure = true;
                root.failed();
                // A wrong password must not cost the user their fingerprint
                // reader, and vice versa: the two paths never share state.
                root.shouldReFocus();
            }
        }
    }

    PamContext {
        id: fingerPam

        configDirectory: "pam"
        config: "fprintd.conf"

        // fprintd narrates the scan through PAM messages. The text is only
        // classified into a state, never displayed or logged, so nothing the
        // reader says can leak through verbatim. "Place your finger on the
        // fingerprint reader" is the idle prompt; anything else it says mid-run
        // means it is working on a sample.
        onPamMessage: {
            const prompt = (this.message ?? "").toLowerCase();
            const isIdlePrompt = prompt.includes("place") || prompt.includes("swipe");
            root.fingerprintState = isIdlePrompt
                ? LockContext.FingerprintEnum.Ready
                : LockContext.FingerprintEnum.Scanning;
        }

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.fingerprintState = LockContext.FingerprintEnum.Ready;
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else if (result == PamResult.Error) { // if timeout or etc..
                root.fingerprintState = LockContext.FingerprintEnum.Error;
                fingerprintRearmTimer.restart();
            } else {
                // Not this user's finger. Say so, keep the password field
                // untouched, and arm the reader again shortly.
                root.fingerprintState = LockContext.FingerprintEnum.Failed;
                fingerprintRearmTimer.restart();
            }
        }
    }

    // Restarting fprintd immediately spins the reader; a short pause also gives
    // the user time to read why the scan did not take.
    Timer {
        id: fingerprintRearmTimer
        interval: 1500
        onTriggered: {
            if (GlobalStates.screenLocked) root.tryFingerUnlock();
        }
    }
}
