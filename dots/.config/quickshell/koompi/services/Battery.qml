pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import QtQuick

/**
 * The battery as koompi-power reads it, published by koompi-shelld.
 *
 * The thresholds stay here rather than being taken from the wire: the crate
 * scores low/critical/full against its own defaults, `Config.options.battery` is
 * what the user edits, and `suspend` has no counterpart in the crate at all.
 */
Singleton {
    id: root

    // UPower's aggregate device, absent on a seat with no laptop battery.
    readonly property var device: ShellServices.power?.display ?? null
    // The first real pack: health and cycle count are per-pack, the aggregate has neither.
    readonly property var pack: ShellServices.power?.primary ?? null

    readonly property bool available: root.device !== null
    readonly property string chargeState: root.device?.state ?? "unknown"
    readonly property bool isCharging: root.chargeState === "charging"
    // UPower's own AC line, right at 100% where a charge state of "fully-charged" is not.
    readonly property bool isPluggedIn: ShellServices.power?.plugged_in ?? false
    readonly property real percentage: (root.device?.percentage ?? 100) / 100
    readonly property bool allowAutomaticSuspend: Config.options.battery.automaticSuspend
    readonly property bool soundEnabled: Config.options.sounds.battery

    readonly property bool isLow: available && (percentage <= Config.options.battery.low / 100)
    readonly property bool isCritical: available && (percentage <= Config.options.battery.critical / 100)
    readonly property bool isSuspending: available && (percentage <= Config.options.battery.suspend / 100)
    readonly property bool isFull: available && (percentage >= Config.options.battery.full / 100)

    readonly property bool isLowAndNotCharging: isLow && !isCharging
    readonly property bool isCriticalAndNotCharging: isCritical && !isCharging
    readonly property bool isSuspendingAndNotCharging: allowAutomaticSuspend && isSuspending && !isCharging
    readonly property bool isFullAndCharging: isFull && isCharging

    readonly property real energyRate: root.device?.energy_rate ?? 0
    readonly property real timeToEmpty: root.device?.time_to_empty ?? 0
    readonly property real timeToFull: root.device?.time_to_full ?? 0

    readonly property real health: root.pack?.health ?? 0
    readonly property int cycleCount: root.pack?.cycle_count ?? 0

    // docs/agents/hooks.md; a machine without koompi-hook gets one shell-log warning
    function fireHook(event) {
        Quickshell.execDetached(["koompi-hook", event, "--",
            "KOOMPI_HOOK_BATTERY_PERCENT=" + Math.round(root.percentage * 100)]);
    }

    onIsLowAndNotChargingChanged: {
        if (!root.available || !isLowAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Low battery"),
            Translation.tr("Consider plugging in your device"),
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
        ])

        if (root.soundEnabled) Audio.playSystemSound("dialog-warning");
        root.fireHook("battery-low");
    }

    onIsCriticalAndNotChargingChanged: {
        if (!root.available || !isCriticalAndNotCharging) return;
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Critically low battery"),
            Translation.tr("Please charge!\nAutomatic suspend triggers at %1%").arg(Config.options.battery.suspend),
            "-u", "critical",
            "-a", "Shell",
            "--hint=int:transient:1",
        ]);

        if (root.soundEnabled) Audio.playSystemSound("suspend-error");
        root.fireHook("battery-critical");
    }

    onIsSuspendingAndNotChargingChanged: {
        if (root.available && isSuspendingAndNotCharging) {
            Quickshell.execDetached(["bash", "-c", `systemctl suspend || loginctl suspend`]);
        }
    }

    onIsFullAndChargingChanged: {
        if (!root.available || !isFullAndCharging) return;
        Quickshell.execDetached([
            "notify-send",
            Translation.tr("Battery full"),
            Translation.tr("Please unplug the charger"),
            "-a", "Shell",
            "--hint=int:transient:1",
        ]);

        if (root.soundEnabled) Audio.playSystemSound("complete");
    }

    // Chime on a transition between two snapshots, never on the first one. The daemon's
    // first snapshot lands after startup, so plugged_in flips false -> true on every
    // login on AC, which UPower read straight from the singleton never did.
    property var lastPlugged: null

    Connections {
        target: ShellServices
        function onPowerChanged() {
            const now = ShellServices.power?.plugged_in ?? null;
            const was = root.lastPlugged;
            root.lastPlugged = now;
            if (was === null || now === null || was === now) return;
            if (!root.available || !root.soundEnabled) return;
            Audio.playSystemSound(now ? "power-plug" : "power-unplug");
        }
    }

    Component.onCompleted: ShellServices.subscribe("power")
}
