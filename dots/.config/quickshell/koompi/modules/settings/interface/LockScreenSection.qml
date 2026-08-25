import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    id: root
    icon: "lock"
    title: Translation.tr("Lock screen")

    // koompi-hw-fingerprint answers from sysfs (exit 0 = a reader is there);
    // fprintd-list prints one " - #N: finger" row per enrolled print.
    property bool readerChecked: false
    property bool readerPresent: false
    property int enrolledCount: 0
    property string fingerprintStatus: {
        if (!root.readerChecked) return Translation.tr("Looking for a fingerprint reader...");
        if (!root.readerPresent) return Translation.tr("No fingerprint reader found");
        if (root.enrolledCount === 0) return Translation.tr("Fingerprint reader found; no finger enrolled yet");
        return Translation.tr("Fingerprint reader found; fingers enrolled: %1").arg(root.enrolledCount);
    }

    Process {
        running: true
        command: ["koompi-hw-fingerprint"]
        onExited: (exitCode, exitStatus) => {
            root.readerPresent = exitCode === 0;
            root.readerChecked = true;
        }
    }
    Process {
        running: true
        command: ["bash", "-c", 'fprintd-list "$(id -un)"']
        stdout: StdioCollector {
            id: printsCollector
            onStreamFinished: {
                root.enrolledCount = (printsCollector.text.match(/^ - #/gm) ?? []).length;
            }
        }
    }

    ConfigSwitch {
        buttonIcon: "water_drop"
        text: Translation.tr('Use Hyprlock (instead of Quickshell)')
        checked: Config.options.lock.useHyprlock
        onCheckedChanged: {
            Config.options.lock.useHyprlock = checked;
        }
    }

    ConfigSwitch {
        buttonIcon: "account_circle"
        text: Translation.tr('Launch on startup')
        checked: Config.options.lock.launchOnStartup
        onCheckedChanged: {
            Config.options.lock.launchOnStartup = checked;
        }
    }

    ContentSubsection {
        title: Translation.tr("Fingerprint")

        RowLayout {
            StyledText {
                Layout.leftMargin: 10
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
                text: root.fingerprintStatus
            }
            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.full
                materialIcon: "fingerprint"
                mainText: Translation.tr("Enrol fingerprint")
                enabled: root.readerPresent
                onClicked: {
                    Quickshell.execDetached(["koompi-setup-fingerprint", "--terminal"]);
                }
                StyledToolTip {
                    text: Translation.tr("Opens a terminal running koompi-setup-fingerprint: enrol a finger, then choose whether sudo and admin prompts accept it")
                }
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Security")

        ConfigSwitch {
            buttonIcon: "settings_power"
            text: Translation.tr('Require password to power off/restart')
            checked: Config.options.lock.security.requirePasswordToPower
            onCheckedChanged: {
                Config.options.lock.security.requirePasswordToPower = checked;
            }
            StyledToolTip {
                text: Translation.tr("Remember that on most devices one can always hold the power button to force shutdown\nThis only makes it a tiny bit harder for accidents to happen")
            }
        }

        ConfigSwitch {
            buttonIcon: "key_vertical"
            text: Translation.tr('Also unlock keyring')
            checked: Config.options.lock.security.unlockKeyring
            onCheckedChanged: {
                Config.options.lock.security.unlockKeyring = checked;
            }
            StyledToolTip {
                text: Translation.tr("This is usually safe and needed for your browser and AI sidebar anyway\nMostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.)")
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Style: general")

        ConfigSwitch {
            buttonIcon: "center_focus_weak"
            text: Translation.tr('Center clock')
            checked: Config.options.lock.centerClock
            onCheckedChanged: {
                Config.options.lock.centerClock = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "info"
            text: Translation.tr('Show "Locked" text')
            checked: Config.options.lock.showLockedText
            onCheckedChanged: {
                Config.options.lock.showLockedText = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "shapes"
            text: Translation.tr('Use varying shapes for password characters')
            checked: Config.options.lock.materialShapeChars
            onCheckedChanged: {
                Config.options.lock.materialShapeChars = checked;
            }
        }
    }
    ContentSubsection {
        title: Translation.tr("Style: Blurred")

        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr('Enable blur')
            checked: Config.options.lock.blur.enable
            onCheckedChanged: {
                Config.options.lock.blur.enable = checked;
            }
        }

        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Extra wallpaper zoom (%)")
            value: Config.options.lock.blur.extraZoom * 100
            from: 1
            to: 150
            stepSize: 2
            onValueChanged: {
                Config.options.lock.blur.extraZoom = value / 100;
            }
        }
    }
}
