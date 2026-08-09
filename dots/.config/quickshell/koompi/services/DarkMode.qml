pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "solar.js" as Solar

/**
 * Light, dark, or automatic. Every mode change in the shell goes through here so
 * that a manual pick is always the one that sticks.
 */
Singleton {
    id: root

    readonly property bool automatic: (Config.options?.light?.darkMode?.automatic ?? false) && (Config?.ready ?? true)
    readonly property bool dark: Appearance.m3colors.darkmode
    readonly property string mode: root.automatic ? "auto" : (root.dark ? "dark" : "light")

    readonly property real fallbackDarkHour: 18
    readonly property real fallbackLightHour: 6

    readonly property real configLatitude: Config.options?.light?.darkMode?.latitude ?? 0
    readonly property real configLongitude: Config.options?.light?.darkMode?.longitude ?? 0
    readonly property bool configLocated: root.configLatitude !== 0 || root.configLongitude !== 0

    property real zoneLatitude: NaN
    property real zoneLongitude: NaN
    readonly property real latitude: root.configLocated ? root.configLatitude : root.zoneLatitude
    readonly property real longitude: root.configLocated ? root.configLongitude : root.zoneLongitude
    readonly property bool located: !isNaN(root.latitude) && !isNaN(root.longitude)

    property var sunrise: null
    property var sunset: null
    property bool polarDay: false
    property bool polarNight: false

    readonly property string sunriseText: root.sunrise ? Qt.locale().toString(root.sunrise, Config.options?.time.format ?? "hh:mm") : ""
    readonly property string sunsetText: root.sunset ? Qt.locale().toString(root.sunset, Config.options?.time.format ?? "hh:mm") : ""

    property bool started: false
    property bool switching: false

    // Every process gets the schedule so it can show it, but only the one that
    // calls load() acts on it. Otherwise the settings app would race the shell
    // into switchwall.
    Component.onCompleted: {
        zoneProc.running = true;
        root.refresh();
    }

    function load() {
        startupDelay.start();
    }

    function setMode(dark) {
        if (Config.options?.light?.darkMode?.automatic)
            Config.options.light.darkMode.automatic = false;
        root.applyMode(dark);
    }

    function setAutomatic(enabled) {
        Config.options.light.darkMode.automatic = enabled;
        if (enabled)
            root.evaluate();
    }

    function toggle() {
        root.setMode(!root.dark);
    }

    function applyMode(dark) {
        if (dark === root.dark)
            return;
        root.switching = true;
        settle.restart();
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", dark ? "dark" : "light", "--noswitch"]);
    }

    function refresh() {
        if (!root.located) {
            root.sunrise = null;
            root.sunset = null;
            root.polarDay = false;
            root.polarNight = false;
            return;
        }
        const times = Solar.sunTimes(new Date(), root.latitude, root.longitude);
        root.sunrise = times.sunrise;
        root.sunset = times.sunset;
        root.polarDay = times.alwaysUp;
        root.polarNight = times.alwaysDown;
    }

    function shouldBeDark() {
        if (root.polarDay)
            return false;
        if (root.polarNight)
            return true;
        if (!root.sunrise || !root.sunset) {
            const hour = DateTime.clock.hours + DateTime.clock.minutes / 60;
            return hour >= root.fallbackDarkHour || hour < root.fallbackLightHour;
        }
        const now = new Date();
        return now < root.sunrise || now >= root.sunset;
    }

    function evaluate() {
        if (!root.started || !root.automatic || root.switching)
            return;
        root.applyMode(root.shouldBeDark());
    }

    function parseZoneCoordinates(iso6709) {
        const parts = iso6709.match(/^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/);
        if (!parts)
            return;
        const degrees = (sign, d, m, s) => (sign === "-" ? -1 : 1) * (Number(d) + Number(m) / 60 + Number(s ?? 0) / 3600);
        root.zoneLatitude = degrees(parts[1], parts[2], parts[3], parts[4]);
        root.zoneLongitude = degrees(parts[5], parts[6], parts[7], parts[8]);
    }

    onLatitudeChanged: {
        root.refresh();
        root.evaluate();
    }
    onAutomaticChanged: root.evaluate()

    Connections {
        target: DateTime.clock
        function onMinutesChanged() {
            root.refresh();
            root.evaluate();
        }
    }

    Timer {
        id: startupDelay
        // switchwall regenerates the whole palette, so stay out of the way of the
        // first-run wallpaper and the theme file's initial load
        interval: 5000
        onTriggered: {
            root.started = true;
            root.refresh();
            root.evaluate();
        }
    }

    Timer {
        id: settle
        interval: 15000
        onTriggered: root.switching = false
    }

    Process {
        id: zoneProc
        command: [Quickshell.shellPath("scripts/timezone-coords.sh")]
        stdout: StdioCollector {
            onStreamFinished: root.parseZoneCoordinates(text.trim())
        }
    }
}
