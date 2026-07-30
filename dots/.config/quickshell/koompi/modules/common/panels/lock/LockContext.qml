import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
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
    // One wallpaper for every monitor, chosen once per lock rather than once
    // per surface, and chosen ahead of time so locking does not wait on a disk
    // walk. prepareWallpaper() runs at startup and after each unlock.
    property string preparedWallpaper: ""
    property real preparedLuminance: 0.5
    property string pickedWallpaper: ""
    property real pickedLuminance: 0.5
    property bool pickedWallpaperFailed: false

    // The configured desktop wallpaper is the last resort. A video wallpaper
    // has no decodable frame here, so its extracted thumbnail stands in.
    readonly property string configuredWallpaper: {
        const raw = Config.options.background.wallpaperPath ?? "";
        const isVideo = [".mp4", ".webm", ".mkv", ".avi", ".mov"].some(ext => raw.endsWith(ext));
        return isVideo ? (Config.options.background.thumbnailPath ?? "") : raw;
    }
    readonly property bool usingPickedWallpaper: !root.pickedWallpaperFailed && root.pickedWallpaper.length > 0
    readonly property string wallpaperPath: root.usingPickedWallpaper ? root.pickedWallpaper : root.configuredWallpaper
    // 0 is black, 1 is white. Drives the scrim so a bright photo is dimmed
    // harder than a dark one and the clock reads on both.
    readonly property real wallpaperLuminance: root.usingPickedWallpaper ? root.pickedLuminance : 0.5

    // Called by a surface whose Image failed to decode. Drops to the configured
    // wallpaper rather than leaving a bare surface.
    function reportWallpaperFailure() {
        if (root.usingPickedWallpaper) root.pickedWallpaperFailed = true;
    }

    function prepareWallpaper() {
        wallpaperPickProc.running = false;
        wallpaperPickProc.running = true;
    }

    function promotePreparedWallpaper() {
        root.pickedWallpaperFailed = false;
        if (root.preparedWallpaper.length > 0) {
            root.pickedWallpaper = root.preparedWallpaper;
            root.pickedLuminance = root.preparedLuminance;
            return;
        }
        // Nothing prepared yet, which happens when the shell locks on startup.
        // The configured wallpaper is shown meanwhile and the pick swaps in as
        // soon as it lands.
        root.prepareWallpaper();
    }

    Process {
        id: wallpaperPickProc
        // The greeter pool first, so the login screen and the lock screen show
        // the same set. A machine without koompi-branding installed has no such
        // directory, so fall back to the user's own wallpaper library rather
        // than locking to a black screen. Every candidate is existence-tested
        // before it is printed.
        readonly property string libraryScript: FileUtils.trimFileProtocol(Directories.scriptPath) + "/colors/random/random_library_wall.sh"
        command: ["sh", "-c",
            'pick=$(find /usr/share/backgrounds/koompi -type f 2>/dev/null | shuf -n 1); '
            + '[ -f "$pick" ] || pick=$("' + wallpaperPickProc.libraryScript + '" --print 2>/dev/null); '
            + '[ -f "$pick" ] || pick=""; '
            + 'lum=""; '
            + '[ -n "$pick" ] && lum=$(magick "$pick" -resize 1x1\\! -format "%[fx:(r+g+b)/3]" info: 2>/dev/null); '
            + 'printf "%s\\n%s\\n" "$pick" "$lum"']
        stdout: StdioCollector {
            id: wallpaperPickCollector
            onStreamFinished: {
                const lines = wallpaperPickCollector.text.split("\n");
                const path = (lines[0] ?? "").trim();
                const luminance = parseFloat((lines[1] ?? "").trim());
                root.preparedWallpaper = path;
                // No ImageMagick, or an image it cannot measure: the middle of
                // the range gives the scrim its neutral value.
                root.preparedLuminance = isNaN(luminance) ? 0.5 : Math.max(0, Math.min(1, luminance));
                // Locked with nothing picked yet: swap it in now rather than
                // leaving the configured wallpaper up for the whole session.
                if (GlobalStates.screenLocked && root.pickedWallpaper.length === 0) {
                    root.promotePreparedWallpaper();
                }
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
