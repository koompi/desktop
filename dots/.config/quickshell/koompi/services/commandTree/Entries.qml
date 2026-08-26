pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * The leaves. One flat list; `group` is a heading, not a level, so nothing here
 * nests and nothing drills.
 *
 * An entry is:
 *   id        stable, unique, `<group>.<thing>`; what the tests and a later
 *             user overlay address a row by
 *   label     what the row reads
 *   group     one of `groups` below
 *   icon      a Material Symbols name
 *   keywords  extra words the fuzzy match should find the row by
 *   when()    optional; false means the row is absent, not greyed
 *   state()   optional; the right-hand column ("on", "16 px", "3")
 *   execute() what Enter runs
 *   verb      optional; the selected row's right-hand verb, "Run" by default
 *
 * Every condition reads a property some service already keeps. None of them
 * spawns anything, so `when` and `state` are safe to re-evaluate on every
 * keystroke; the two that had no home are probed once in Conditions.qml.
 */
QtObject {
    id: root

    required property Conditions conditions

    readonly property var groups: [
        ({ id: "toggles", label: Translation.tr("Toggles") }),
        ({ id: "display", label: Translation.tr("Display") }),
        ({ id: "session", label: Translation.tr("Session") }),
        ({ id: "system", label: Translation.tr("System") })
    ]

    readonly property string on: Translation.tr("on")
    readonly property string off: Translation.tr("off")

    // The shell's text size, the one knob koompi-theme moves together with GTK
    // and the terminal (modules/common/Config.qml:219, dots/.local/bin/koompi-theme:23-25).
    readonly property int textSize: Config.options?.appearance?.fonts?.baseSize ?? 16
    readonly property int textSizeMin: 9
    readonly property int textSizeMax: 24
    readonly property int textSizeDefault: 16

    function setTextSize(value) {
        Quickshell.execDetached(["koompi-theme", "text-size", String(value)]);
    }

    // A command whose output is the point runs where it can be read, in the
    // terminal shell actions already use (modules/common/Config.qml:273, the
    // same one LauncherSearch.qml hands a sudo command). The trailing read
    // keeps a failure on screen instead of closing the window over it, the way
    // the update badge does (modules/koompi/bar/UpdateBadge.qml:26-32).
    function inTerminal(id, script) {
        Quickshell.execDetached(["koompi-launch", "--id", id, "--terminal", Config.options.apps.terminal, "--", "bash", "-c", `${script}; read -rsn1 -p 'Done. Press any key to close.'`]);
    }

    readonly property var all: [
        ({
            id: "toggles.night-light",
            label: Translation.tr("Night light"),
            group: "toggles",
            icon: "bedtime",
            keywords: "blue warm colour color temperature sunset gamma hyprsunset",
            // services/Hyprsunset.qml:149 toggleTemperature, :28 temperatureActive
            state: () => Hyprsunset.temperatureActive ? root.on : root.off,
            execute: () => Hyprsunset.toggleTemperature()
        }),
        ({
            id: "toggles.keep-awake",
            label: Translation.tr("Keep awake"),
            group: "toggles",
            icon: "coffee",
            keywords: "caffeine idle inhibit sleep lock presentation",
            // services/Idle.qml:38 toggleInhibit, :14 inhibit
            state: () => Idle.inhibit ? root.on : root.off,
            execute: () => Idle.toggleInhibit()
        }),
        ({
            id: "toggles.do-not-disturb",
            label: Translation.tr("Do not disturb"),
            group: "toggles",
            icon: "notifications_paused",
            keywords: "silent quiet notifications dnd mute toast",
            // services/Notifications.qml:112 silent, flipped the way the sidebar
            // switch does at modules/koompi/sidebarRight/notifications/NotificationList.qml:55
            state: () => Notifications.silent ? root.on : root.off,
            execute: () => {
                Notifications.silent = !Notifications.silent;
            }
        }),
        ({
            id: "toggles.dark-mode",
            label: Translation.tr("Dark mode"),
            group: "toggles",
            icon: "dark_mode",
            keywords: "light theme appearance night day",
            // services/DarkMode.qml:69 toggle, :18 dark
            state: () => DarkMode.dark ? root.on : root.off,
            execute: () => DarkMode.toggle()
        }),
        ({
            id: "toggles.charge-limit",
            label: Translation.tr("Battery charge limit"),
            group: "toggles",
            icon: "battery_saver",
            keywords: "battery charging threshold longevity",
            // services/ChargeLimit.qml:23 supported, :24 enabled, :26 endThreshold, :30 setEnabled
            when: () => ChargeLimit.supported,
            state: () => ChargeLimit.enabled ? `${ChargeLimit.endThreshold}%` : root.off,
            execute: () => ChargeLimit.setEnabled(!ChargeLimit.enabled)
        }),

        ({
            id: "display.text-bigger",
            label: Translation.tr("Text bigger"),
            group: "display",
            icon: "text_increase",
            keywords: "font size scale zoom larger accessibility",
            // dots/.local/bin/koompi-theme:24-25 clamps to 9-24; the row is gone at the top
            when: () => root.textSize < root.textSizeMax,
            state: () => Translation.tr("%1 px").arg(root.textSize),
            execute: () => root.setTextSize(root.textSize + 1)
        }),
        ({
            id: "display.text-smaller",
            label: Translation.tr("Text smaller"),
            group: "display",
            icon: "text_decrease",
            keywords: "font size scale zoom smaller accessibility",
            when: () => root.textSize > root.textSizeMin,
            state: () => Translation.tr("%1 px").arg(root.textSize),
            execute: () => root.setTextSize(root.textSize - 1)
        }),
        ({
            id: "display.text-reset",
            label: Translation.tr("Reset text size"),
            group: "display",
            icon: "format_size",
            keywords: "font size default",
            // dots/.local/bin/koompi-theme:23 TEXT_PX_DEFAULT; nothing to reset at the default
            when: () => root.textSize !== root.textSizeDefault,
            execute: () => Quickshell.execDetached(["koompi-theme", "text-size", "reset"])
        }),

        ({
            id: "session.screensaver",
            label: Translation.tr("Start screensaver"),
            group: "session",
            icon: "monitor",
            keywords: "idle blank clock away",
            // modules/koompi/screensaver/Screensaver.qml:15-21: open() sets the
            // same flag and refuses under a session lock, so the guard comes too
            execute: () => {
                if (!GlobalStates.screenLocked)
                    GlobalStates.screensaverOpen = true;
            }
        }),
        ({
            id: "session.lock",
            label: Translation.tr("Lock screen"),
            group: "session",
            icon: "lock",
            keywords: "lockscreen away secure loginctl",
            // modules/common/functions/Session.qml:21
            execute: () => Session.lock()
        }),
        ({
            id: "session.hibernate",
            label: Translation.tr("Hibernate"),
            group: "session",
            icon: "downloading",
            keywords: "suspend to disk sleep power resume",
            // services/SessionWarnings.qml:16 canHibernate, the same gate the
            // session screen's button uses (modules/koompi/sessionScreen/SessionScreen.qml:175)
            when: () => SessionWarnings.canHibernate,
            // modules/common/functions/Session.qml:40
            execute: () => Session.hibernate()
        }),

        ({
            id: "system.reload",
            label: Translation.tr("Reload desktop"),
            group: "system",
            icon: "refresh",
            keywords: "restart shell quickshell hyprland qs",
            // dots/.local/bin/koompi-reload:29-34
            execute: () => Quickshell.execDetached(["koompi-reload"])
        }),
        ({
            id: "system.snapshot",
            label: Translation.tr("Create system snapshot"),
            group: "system",
            icon: "backup",
            keywords: "btrfs snapper rollback restore point backup",
            // dots/.local/bin/koompi-snapshot:48-61; snapper writes to stdout and
            // may want a password, so it runs where both are visible
            execute: () => root.inTerminal("koompi-snapshot", "koompi-snapshot create --description 'Search: create system snapshot'")
        }),
        ({
            id: "system.update",
            label: Translation.tr("Install updates"),
            group: "system",
            icon: "system_update",
            keywords: "upgrade pacman packages system",
            // services/Updates.qml:24 count; the command is the update badge's
            // (modules/koompi/bar/UpdateBadge.qml:30-31), which is dots/.local/bin/koompi-update:4
            state: () => Updates.count > 0 ? String(Updates.count) : "",
            execute: () => root.inTerminal("koompi-update", "koompi update")
        }),
        ({
            id: "system.check-updates",
            label: Translation.tr("Check for updates"),
            group: "system",
            icon: "sync",
            keywords: "refresh pacman checkupdates packages",
            // services/Updates.qml:22 available is `which checkupdates`
            // (:73-77); without it refresh() returns having done nothing
            when: () => Updates.available,
            state: () => Updates.checking ? Translation.tr("checking") : "",
            // services/Updates.qml:48
            execute: () => Updates.refresh()
        }),
        ({
            id: "system.crash-report",
            label: Translation.tr("Latest crash report"),
            group: "system",
            icon: "bug_report",
            keywords: "coredump diagnose bug core dumped",
            when: () => root.conditions.crashReportCount > 0,
            state: () => String(root.conditions.crashReportCount),
            // dots/.local/bin/koompi-crash-diagnose:226 opens a report the same way
            execute: () => Quickshell.execDetached(["koompi-launch", "xdg-open", root.conditions.newestCrashReport])
        }),
        ({
            id: "system.fingerprint",
            label: Translation.tr("Set up fingerprint"),
            group: "system",
            icon: "fingerprint",
            keywords: "finger reader enrol enroll biometric fprintd sudo",
            // A row about a reader teaches nothing on a machine without one
            when: () => root.conditions.fingerprintReader,
            // dots/.local/bin/koompi-setup-fingerprint:32 --terminal, the button
            // at modules/settings/interface/LockScreenSection.qml:81
            execute: () => Quickshell.execDetached(["koompi-setup-fingerprint", "--terminal"])
        })
    ]
}
