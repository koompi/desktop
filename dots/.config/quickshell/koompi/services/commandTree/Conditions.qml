import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

/**
 * The two gates a command-tree leaf needs that no existing singleton already
 * holds. Everything else a `when` asks about (Idle, Hyprsunset, Notifications,
 * ChargeLimit, Updates, SessionWarnings, Config) is read straight off the
 * service that owns it.
 *
 * Neither of these costs anything per keystroke: the reader is probed once at
 * load, the way SessionWarnings.qml:44 probes CanHibernate, and the crash
 * folder is watched by the same FolderListModel the launcher already uses for
 * ~/.config/koompi/actions. No timer is introduced here.
 */
QtObject {
    id: root

    // koompi-hw-fingerprint reads sysfs and exits 0 when a reader is plugged in
    // (dots/.local/bin/koompi-hw-fingerprint:3). Probed once; a reader appearing
    // later is a reload away, which is what the Settings page assumes too
    // (modules/settings/interface/LockScreenSection.qml:28).
    property bool fingerprintReader: false

    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
    // koompi-crash-diagnose writes 0600 reports named <timestamp>-<comm>-<pid>.md
    // here (dots/.local/bin/koompi-crash-diagnose:34,182).
    readonly property string crashDir: `${root.stateHome}/koompi/crash`
    readonly property int crashReportCount: crashReports.count
    // Sorted by name, reversed: the names start with the timestamp, so row 0 is
    // the newest report. Empty while the folder does not exist.
    readonly property string newestCrashReport: crashReports.count > 0 ? FileUtils.trimFileProtocol(String(crashReports.get(0, "filePath"))) : ""

    readonly property Process readerProbe: Process {
        running: true
        command: ["koompi-hw-fingerprint"]
        onExited: (exitCode, exitStatus) => {
            root.fingerprintReader = (exitCode === 0);
        }
    }

    readonly property FolderListModel crashReports: FolderListModel {
        folder: `file://${root.crashDir}`
        nameFilters: ["*.md"]
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
        sortReversed: true
    }
}
