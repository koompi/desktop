pragma Singleton
pragma ComponentBehavior: Bound

// From https://github.com/caelestia-dots/shell with modifications.
// License: GPLv3

import qs.services
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

/**
 * For managing brightness of monitors, internal and external.
 *
 * koompi-brightness holds both backends: logind `SetBrightness` for the internal panel,
 * which is why there is no udev rule to install, and `ddcutil` for external ones. The
 * `ddcutil detect` at startup and the `brightnessctl` fork per animation frame are gone;
 * a frame is now a line on the daemon's stdin, which is what the crate's zero debounce on
 * the internal panel is for.
 *
 * The anti-flashbang capture stays here: the multiplier is a screen grab the shell takes,
 * so the shell keeps the requested brightness and sends the product.
 */
Singleton {
    id: root
    signal brightnessChanged()

    readonly property list<BrightnessMonitor> monitors: Quickshell.screens.map(screen => monitorComp.createObject(root, {
        screen
    }))

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.screen === screen);
    }

    function increaseBrightness(): void {
        // if gamma is not yet 100, first increase gamma
        if (Hyprsunset.gamma !== 100) {
            Hyprsunset.setGamma(Hyprsunset.gamma + 5);
            return;
        }

        const focusedName = Hyprland.focusedMonitor.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor)
            monitor.setBrightness(monitor.brightness + 0.05);
    }

    function decreaseBrightness(): void {
        const focusedName = Hyprland.focusedMonitor.name;
        const monitor = monitors.find(m => focusedName === m.screen.name);
        if (monitor && monitor.brightness > 0) 
            monitor.setBrightness(monitor.brightness - 0.05);
        // if brightness is 0, then decrease gamma
        else {
            Hyprsunset.setGamma(Hyprsunset.gamma - 5);
        }
    }

    reloadableId: "brightness"

    component BrightnessMonitor: QtObject {
        id: monitor

        required property ShellScreen screen

        readonly property var panel: ShellServices.brightnessPanel(monitor.screen.name)
        readonly property bool ready: monitor.panel !== null
        readonly property bool isDdc: monitor.panel?.backend === "ddc"
        readonly property int rawMaxBrightness: monitor.panel?.raw_max ?? 100

        property real brightness
        property real brightnessMultiplier: 1.0
        property real multipliedBrightness: Math.max(0, Math.min(1, brightness * (Config.options.light.antiFlashbang.enable ? brightnessMultiplier : 1)))
        readonly property bool animateChanges: !monitor.isDdc

        // A brightness key pressed outside the shell moves the panel too and the daemon
        // follows sysfs, so a reading can disagree with what was last asked for. Two ways
        // it disagrees without anyone else touching it: our own writes echo back rounded,
        // logind floors to whole percent, and during a ramp the echo lags the frame being
        // drawn. Adopting either would walk the value down or fight the animation.
        property bool synced: false
        property double lastWrite: 0
        // A value taken from the panel is not a value to send back to it, and it must not
        // ramp there from wherever this object started. `raw -> fraction -> raw` is lossy:
        // 52363 of 174545 reads as 0.29999, which writes back as 29%, so a shell that
        // seeded itself through the ramp walked the panel down a percent every launch.
        property bool seeding: false

        function adopt(): void {
            if (!monitor.ready) {
                monitor.synced = false;
                return;
            }
            const reported = monitor.panel.brightness;
            if (monitor.synced) {
                if (Date.now() - monitor.lastWrite < 500)
                    return;
                if (Math.abs(reported - monitor.multipliedBrightness) <= 0.01)
                    return;
            }
            const factor = Config.options.light.antiFlashbang.enable ? Math.max(0.01, monitor.brightnessMultiplier) : 1;
            monitor.seeding = true;
            monitor.brightness = Math.max(0, Math.min(1, reported / factor));
            monitor.seeding = false;
            monitor.synced = true;
        }

        // The daemon's state, not `panel`. Nothing observes that binding until something
        // reads it, so QML leaves it dirty and its change signal arrives whenever the
        // first read happens to be, which is far too late to seed a value from.
        readonly property Connections published: Connections {
            target: ShellServices
            function onBrightnessChanged() {
                monitor.adopt();
            }
        }

        // The daemon sends one state per change, and a panel nobody is moving changes
        // never. A monitor created after that first snapshot would sit at zero forever,
        // waiting for a signal that has already been and gone.
        Component.onCompleted: monitor.adopt()

        onBrightnessChanged: {
            if (!monitor.ready) return;
            root.brightnessChanged();
        }

        Behavior on multipliedBrightness {
            enabled: monitor.animateChanges && !monitor.seeding
            NumberAnimation {
                duration: Appearance.animationDuration.fast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
        // Every frame of the ramp above. The daemon debounces per backend - 300 ms for
        // DDC, nothing for the internal panel - so the rate limiting the timer here used
        // to do belongs on the side that knows which backend it is talking to.
        onMultipliedBrightnessChanged: {
            if (!monitor.ready)
                return;
            // What the panel already reports, to the bit: this frame came from the daemon
            // rather than from anyone asking for it.
            if (monitor.panel.brightness === monitor.multipliedBrightness)
                return;
            monitor.lastWrite = Date.now();
            ShellServices.command("brightness", "set_brightness", {
                panel: monitor.panel.id,
                value: monitor.multipliedBrightness
            });
        }

        function setBrightness(value: real): void {
            value = Math.max(0, Math.min(1, value));
            monitor.brightness = value;
        }

        function setBrightnessMultiplier(value: real): void {
            monitor.brightnessMultiplier = value;
        }
    }

    Component {
        id: monitorComp

        BrightnessMonitor {}
    }

    // Anti-flashbang
    property int workspaceAnimationDelay: 500
    // A capture round trip is ~400ms-1s, so a 30ms debounce only queued work
    // that could never keep up with a terminal rewriting its title.
    property int contentSwitchDelay: 500
    property string screenshotDir: "/tmp/quickshell/brightness/antiflashbang"
    function brightnessMultiplierForLightness(x: real): real {
        // I hand picked some values and fitted an exponential curve for this
        // 6.600135 + 216.360356 * e^(-0.0811129189x)
        // Division by 100 is to normalize to [0, 1]
        return (6.600135 + 216.360356 * Math.pow(Math.E, -0.0811129189 * x)) / 100.0;
    }
    Variants {
        model: Quickshell.screens
        Scope {
            id: screenScope
            required property var modelData
            property string screenName: modelData.name
            property string screenshotPath: `${root.screenshotDir}/screenshot-${screenName}.png`
            Connections {
                enabled: Config.options.light.antiFlashbang.enable && Appearance.m3colors.darkmode
                target: Hyprland
                function onRawEvent(event) {
                    if (["activewindowv2", "windowtitlev2"].includes(event.name)) {
                        screenshotTimer.interval = root.contentSwitchDelay;
                        screenshotTimer.restart();
                    } else if (["workspacev2"].includes(event.name)) {
                        screenshotTimer.interval = root.workspaceAnimationDelay;
                        screenshotTimer.restart();
                    }
                }
            }

            Timer {
                id: screenshotTimer
                interval: 700 // This is what I have for a Hyprland ws anim
                onTriggered: {
                    // Killing an in-flight grim to start a fresh one means a
                    // busy title bar never produces a lightness at all.
                    if (screenshotProc.running) {
                        restart();
                        return;
                    }
                    screenshotProc.running = true;
                }
            }

            Process {
                id: screenshotProc
                command: ["bash", "-c",
                    `mkdir -p '${StringUtils.shellSingleQuoteEscape(root.screenshotDir)}'`
                    + ` && grim -o '${StringUtils.shellSingleQuoteEscape(screenScope.screenName)}' -`
                    + ` | magick png:- -colorspace Gray -format "%[fx:mean*100]" info:`
                ]
                stdout: StdioCollector {
                    id: lightnessCollector
                    onStreamFinished: {
                        Quickshell.execDetached(["rm", screenScope.screenshotPath]); // Cleanup
                        const lightness = lightnessCollector.text
                        const newMultiplier = root.brightnessMultiplierForLightness(parseFloat(lightness))
                        Brightness.getMonitorForScreen(screenScope.modelData).setBrightnessMultiplier(newMultiplier)
                    }
                }
            }
        }
    }

    // External trigger points

    IpcHandler {
        target: "brightness"

        function increment() {
            onPressed: root.increaseBrightness()
        }

        function decrement() {
            onPressed: root.decreaseBrightness()
        }
    }

    GlobalShortcut {
        name: "brightnessIncrease"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    GlobalShortcut {
        name: "brightnessDecrease"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }

    Component.onCompleted: ShellServices.subscribe("brightness")
}
