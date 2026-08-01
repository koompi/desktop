pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "ics.js" as Ics

Singleton {
    id: root

    readonly property string url: Persistent.states.calendar.icsUrl
    readonly property bool connected: url.length > 0

    property var events: []
    property bool loading: false
    property string error: ""
    property date lastSync

    // Google publishes the whole calendar; only the near future is worth showing.
    readonly property int daysAhead: 30

    function connect(newUrl) {
        const trimmed = (newUrl ?? "").trim();
        if (!/^https?:\/\//.test(trimmed)) {
            root.error = Translation.tr("That does not look like a calendar URL");
            return false;
        }
        // The embed link is the easy one to grab by mistake; it serves HTML.
        if (trimmed.includes("/calendar/embed") || trimmed.includes("/calendar/r")) {
            root.error = Translation.tr("That is the embed link. Use Settings > your calendar > Secret address in iCal format, which ends in .ics");
            return false;
        }
        root.error = "";
        Persistent.states.calendar.icsUrl = trimmed;
        root.refresh();
        return true;
    }

    function disconnect() {
        Persistent.states.calendar.icsUrl = "";
        root.events = [];
        root.error = "";
    }

    function refresh() {
        if (!root.connected || root.loading)
            return;
        root.loading = true;
        // Set the command here, not as a binding: `connected` and `command` both
        // depend on `url`, and QML does not order them, so a bound command still
        // held "" when connected fired the first refresh.
        fetchProc.command = ["curl", "-sSL", "--max-time", "20", root.url];
        fetchProc.running = true;
    }

    // Events starting on a given day.
    function eventsOn(date) {
        return root.events.filter(e => e.start.getFullYear() === date.getFullYear() && e.start.getMonth() === date.getMonth() && e.start.getDate() === date.getDate());
    }

    function hasEventsOn(date) {
        return root.eventsOn(date).length > 0;
    }

    onConnectedChanged: if (connected) root.refresh()
    Component.onCompleted: if (connected) root.refresh()

    function ingest(body) {
        root.loading = false;
        if (body.indexOf("BEGIN:VCALENDAR") === -1) {
            root.error = Translation.tr("That URL did not return a calendar");
            return;
        }
        const from = new Date();
        from.setHours(0, 0, 0, 0);
        const to = new Date(from.getTime() + root.daysAhead * 86400000);
        try {
            root.events = Ics.parseEvents(body, from, to);
            root.error = "";
            root.lastSync = new Date();
        } catch (e) {
            root.error = Translation.tr("Could not read that calendar");
        }
    }

    Process {
        id: fetchProc
        // -L: Google redirects the secret address. --max-time: never hang the panel.
        stdout: StdioCollector {
            id: fetchOut
            // A real calendar is megabytes. Parsing on exit can catch a stream
            // that has not finished draining, so parse when it says it is done.
            waitForEnd: true
            onStreamFinished: root.ingest(fetchOut.text)
        }
        stderr: StdioCollector {
            id: fetchErr
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.loading = false;
                root.error = fetchErr.text.trim() || Translation.tr("Could not reach Google Calendar");
            }
        }
    }

    // Calendars change slowly; hourly is plenty and costs one curl. Retry every
    // minute while broken: the shell starts before the network does, and that
    // first failure otherwise stands for an hour.
    Timer {
        interval: root.error.length > 0 ? 60000 : 3600000
        repeat: true
        running: root.connected
        onTriggered: root.refresh()
    }
}
