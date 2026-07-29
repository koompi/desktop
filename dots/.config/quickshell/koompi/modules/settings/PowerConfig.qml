import QtQuick
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "battery_full"
        title: Translation.tr("Battery")

        StyledText {
            visible: !Battery.available
            text: Translation.tr("No battery detected")
            color: Appearance.colors.colSubtext
        }

        StyledText {
            visible: Battery.available
            text: Translation.tr("Charge: %1%").arg(Math.round((Battery.percentage ?? 0) * 100))
        }
        StyledText {
            visible: Battery.available
            text: {
                if (Battery.chargeState == UPowerDeviceState.FullyCharged)
                    return Translation.tr("State: Fully charged");
                if (Battery.isCharging)
                    return Translation.tr("State: Charging");
                if (Battery.isPluggedIn)
                    return Translation.tr("State: Plugged in");
                return Translation.tr("State: Discharging");
            }
        }
        StyledText {
            visible: Battery.available && ((Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty) ?? 0) > 0
            text: {
                function formatTime(seconds) {
                    var h = Math.floor(seconds / 3600);
                    var m = Math.floor((seconds % 3600) / 60);
                    if (h > 0)
                        return `${h}h, ${m}m`;
                    else
                        return `${m}m`;
                }
                if (Battery.isCharging)
                    return Translation.tr("Time to full: %1").arg(formatTime(Battery.timeToFull));
                else
                    return Translation.tr("Time to empty: %1").arg(formatTime(Battery.timeToEmpty));
            }
        }
        StyledText {
            visible: Battery.available && (Battery.health ?? 0) > 0
            text: Translation.tr("Health: %1%").arg((Battery.health ?? 0).toFixed(1))
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "speed"
        title: Translation.tr("Power profile")

        ConfigSelectionArray {
            currentValue: PowerProfiles.profile
            onSelected: newValue => {
                PowerProfiles.profile = newValue;
            }
            options: {
                const opts = [
                    {
                        displayName: Translation.tr("Power saver"),
                        icon: "energy_savings_leaf",
                        value: PowerProfile.PowerSaver
                    },
                    {
                        displayName: Translation.tr("Balanced"),
                        icon: "airwave",
                        value: PowerProfile.Balanced
                    },
                ];
                if (PowerProfiles.hasPerformanceProfile) {
                    opts.push({
                        displayName: Translation.tr("Performance"),
                        icon: "local_fire_department",
                        value: PowerProfile.Performance
                    });
                }
                return opts;
            }
        }
    }

    ContentSection {
        icon: "battery_alert"
        title: Translation.tr("Battery thresholds")

        ConfigSpinBox {
            icon: "battery_low"
            text: Translation.tr("Low warning (%)")
            value: Config.options.battery.low
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.battery.low = value;
            }
        }
        ConfigSpinBox {
            icon: "battery_alert"
            text: Translation.tr("Critical warning (%)")
            value: Config.options.battery.critical
            from: 0
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.battery.critical = value;
            }
        }
        ConfigSpinBox {
            icon: "bedtime"
            text: Translation.tr("Suspend at (%)")
            value: Config.options.battery.suspend
            from: 0
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.battery.suspend = value;
            }
        }
        ConfigSwitch {
            buttonIcon: "bedtime"
            text: Translation.tr("Automatic suspend")
            checked: Config.options.battery.automaticSuspend
            onCheckedChanged: {
                Config.options.battery.automaticSuspend = checked;
            }
        }
    }

    ContentSection {
        icon: "coffee"
        title: Translation.tr("Keep awake")

        ConfigSwitch {
            buttonIcon: "coffee"
            text: Translation.tr("Keep system awake")
            checked: Idle.inhibit
            onCheckedChanged: {
                Idle.toggleInhibit(checked);
            }
        }
    }
}
