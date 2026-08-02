pragma Singleton

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Services.UPower

/**
 * One gate for the shell's unconditional background polling, and the AC/battery
 * power profile swap that hangs off the same signal.
 *
 * `awake` is false when nothing on screen can show the result of a poll, so a
 * poller gated on it stops instead of feeding a surface nobody is looking at.
 * `saving` is the `power.saveOnBattery` switch: on battery the shell does the
 * same work half as often.
 */
Singleton {
    id: root

    readonly property bool onBattery: UPower.onBattery
    readonly property bool saving: (Config.options?.power?.saveOnBattery ?? true) && root.onBattery

    // The session lock is the only screen-off signal the shell already has.
    // hypridle locks five minutes before it turns the displays off, so gating
    // here covers the whole displays-off window too.
    readonly property bool awake: !GlobalStates.screenLocked

    // ponytail: one multiplier for the whole shell, not a knob per service.
    // Per-service rates if one of them ever needs to differ.
    readonly property int factor: root.saving ? 2 : 1

    function interval(ms) {
        return ms * root.factor;
    }

    // `power.autoProfileOnBattery`, off by default: overriding a profile the
    // user picked by hand is worse than leaving it alone.
    readonly property bool autoProfile: Config.options?.power?.autoProfileOnBattery ?? false

    // What the user runs on AC, so plugging back in undoes the swap exactly
    // instead of landing on "balanced" for everyone.
    property int acProfile: PowerProfile.Balanced

    onOnBatteryChanged: {
        if (!root.autoProfile)
            return;
        PowerProfiles.profile = root.onBattery ? PowerProfile.PowerSaver : root.acProfile;
    }

    Connections {
        // Null while off, so a shell that never uses this never opens PPD.
        target: root.autoProfile ? PowerProfiles : null
        function onProfileChanged() {
            if (!root.onBattery)
                root.acProfile = PowerProfiles.profile;
        }
    }
}
