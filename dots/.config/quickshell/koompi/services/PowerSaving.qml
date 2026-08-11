pragma Singleton

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell

/**
 * One gate for the shell's unconditional background polling, and the power profile
 * surface the whole shell writes through.
 *
 * `awake` is false when nothing on screen can show the result of a poll, so a
 * poller gated on it stops instead of feeding a surface nobody is looking at.
 * `saving` is the `power.saveOnBattery` switch: on battery the shell does the
 * same work half as often.
 *
 * koompi-power owns both UPower and power-profiles-daemon, so nothing here opens a
 * second client of either. Profile names are the daemon's own strings, per
 * shell-services/shelld/PROTOCOL.md.
 */
Singleton {
    id: root

    readonly property bool onBattery: ShellServices.power?.on_battery ?? false
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

    readonly property string profile: ShellServices.power?.profiles?.active ?? ""
    readonly property var availableProfiles: ShellServices.power?.profiles?.available ?? []
    readonly property bool hasPerformanceProfile: root.availableProfiles.includes("performance")
    // Non-empty names the reason the daemon is throttling, usually `lap-detected`.
    readonly property string degraded: ShellServices.power?.profiles?.degraded ?? ""

    function setProfile(name) {
        if (name === root.profile)
            return;
        ShellServices.command("power", "set_profile", {
            profile: name
        });
    }

    // `power.autoProfileOnBattery`, off by default: overriding a profile the
    // user picked by hand is worse than leaving it alone.
    readonly property bool autoProfile: Config.options?.power?.autoProfileOnBattery ?? false

    // What the user runs on AC, so plugging back in undoes the swap exactly
    // instead of landing on "balanced" for everyone.
    property string acProfile: "balanced"

    onProfileChanged: {
        if (!root.onBattery && root.profile.length > 0)
            root.acProfile = root.profile;
    }

    onOnBatteryChanged: {
        if (!root.autoProfile)
            return;
        root.setProfile(root.onBattery ? "power-saver" : root.acProfile);
    }

    Component.onCompleted: ShellServices.subscribe("power")
}
