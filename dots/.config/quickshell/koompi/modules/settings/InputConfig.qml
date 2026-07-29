import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property var pointerSensitivity: null
    property var naturalScroll: null
    readonly property string hyprlandInputConfigPath: `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/general.lua`

    Process {
        id: sensitivityProc
        running: true
        command: ["hyprctl", "getoption", "input:sensitivity", "-j"]
        stdout: StdioCollector {
            id: sensitivityCollector
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(sensitivityCollector.text);
                    root.pointerSensitivity = parsed?.float ?? null;
                } catch (e) {
                    root.pointerSensitivity = null;
                }
            }
        }
    }

    Process {
        id: naturalScrollProc
        running: true
        command: ["hyprctl", "getoption", "input:touchpad:natural_scroll", "-j"]
        stdout: StdioCollector {
            id: naturalScrollCollector
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(naturalScrollCollector.text);
                    root.naturalScroll = parsed?.bool ?? null;
                } catch (e) {
                    root.naturalScroll = null;
                }
            }
        }
    }

    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Keyboard")

        ConfigRow {
            MaterialSymbol {
                text: "keyboard"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: HyprlandXkb.currentLayoutName || Translation.tr("Unknown layout")
                }
                StyledText {
                    visible: (HyprlandXkb.currentLayoutCode ?? "") !== ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Current layout") + ` • ${HyprlandXkb.currentLayoutCode}`
                }
            }
        }

        Repeater {
            model: ScriptModel {
                values: HyprlandXkb.layoutCodes
            }
            delegate: ConfigRow {
                id: layoutRow
                required property var modelData

                MaterialSymbol {
                    text: "language"
                    iconSize: Appearance.font.pixelSize.larger
                    color: layoutRow.modelData === HyprlandXkb.currentLayoutCode ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: layoutRow.modelData
                }
                StyledText {
                    visible: layoutRow.modelData === HyprlandXkb.currentLayoutCode
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                    text: Translation.tr("Active")
                }
            }
        }

        RowLayout {
            StyledText {
                Layout.leftMargin: 10
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
                text: Translation.tr("Keyboard layouts are configured in the Hyprland config (input.kb_layout)")
            }
            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.full
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open config")
                onClicked: {
                    Quickshell.execDetached(["xdg-open", root.hyprlandInputConfigPath]);
                }
                StyledToolTip {
                    text: root.hyprlandInputConfigPath
                }
            }
        }
    }

    ContentSection {
        icon: "keyboard_alt"
        title: Translation.tr("On-screen keyboard")

        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr("Pinned on startup")
            checked: Config.options?.osk.pinnedOnStartup ?? false
            onCheckedChanged: {
                Config.options.osk.pinnedOnStartup = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Layout")
            tooltip: Translation.tr("Automatically follows the active Hyprland layout when switching")

            ConfigSelectionArray {
                currentValue: Config.options?.osk.layout ?? ""
                onSelected: newValue => {
                    Config.options.osk.layout = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("English (US)"),
                        value: "English (US)"
                    },
                    {
                        displayName: Translation.tr("German"),
                        value: "German"
                    },
                    {
                        displayName: Translation.tr("Russian"),
                        value: "Russian"
                    }
                ]
            }
        }
    }

    ContentSection {
        icon: "mouse"
        title: Translation.tr("Pointer")

        ConfigRow {
            MaterialSymbol {
                text: "speed"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Sensitivity")
            }
            StyledText {
                color: Appearance.colors.colSubtext
                text: root.pointerSensitivity !== null ? Number(root.pointerSensitivity).toFixed(2) : Translation.tr("Unknown")
            }
        }

        ConfigRow {
            MaterialSymbol {
                text: "swipe_vertical"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Touchpad natural scrolling")
            }
            StyledText {
                color: Appearance.colors.colSubtext
                text: root.naturalScroll === null ? Translation.tr("Unknown") : (root.naturalScroll ? Translation.tr("On") : Translation.tr("Off"))
            }
        }

        RowLayout {
            StyledText {
                Layout.leftMargin: 10
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
                text: Translation.tr("Pointer options are configured in the Hyprland config (input section)")
            }
            RippleButtonWithIcon {
                buttonRadius: Appearance.rounding.full
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open config")
                onClicked: {
                    Quickshell.execDetached(["xdg-open", root.hyprlandInputConfigPath]);
                }
                StyledToolTip {
                    text: root.hyprlandInputConfigPath
                }
            }
        }
    }
}
