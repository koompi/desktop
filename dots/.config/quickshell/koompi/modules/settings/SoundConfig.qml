import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Output")

        StyledText {
            visible: !Audio.ready
            text: Translation.tr("No output device found")
            color: Appearance.colors.colSubtext
        }

        ConfigSlider {
            text: Translation.tr("Volume")
            buttonIcon: "volume_up"
            from: 0
            to: 1
            value: Audio.sink?.audio?.volume ?? 0
            onValueChanged: {
                if (Audio.sink?.audio) Audio.sink.audio.volume = value;
            }
        }
        ConfigSwitch {
            buttonIcon: "volume_off"
            text: Translation.tr("Mute")
            checked: Audio.sink?.audio?.muted ?? false
            onCheckedChanged: {
                if (Audio.sink?.audio) Audio.sink.audio.muted = checked;
            }
        }

        Repeater {
            model: ScriptModel {
                values: Audio.outputDevices
            }
            delegate: ConfigRow {
                id: outputRow
                required property var modelData
                readonly property var device: outputRow.modelData
                readonly property bool isDefault: outputRow.device?.id === Audio.sink?.id

                MaterialSymbol {
                    text: "speaker"
                    iconSize: Appearance.font.pixelSize.larger
                    color: outputRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: outputRow.device ? Audio.friendlyDeviceName(outputRow.device) : Translation.tr("Unknown device")
                    }
                    StyledText {
                        visible: outputRow.isDefault
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Default")
                    }
                }
                RippleButtonWithIcon {
                    visible: !outputRow.isDefault
                    materialIcon: "check"
                    mainText: Translation.tr("Set default")
                    buttonRadius: Appearance.rounding.small
                    onClicked: {
                        Audio.setDefaultSink(outputRow.device);
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "mic"
        title: Translation.tr("Input")

        StyledText {
            visible: !Audio.source
            text: Translation.tr("No input device found")
            color: Appearance.colors.colSubtext
        }

        ConfigSlider {
            text: Translation.tr("Volume")
            buttonIcon: "mic"
            from: 0
            to: 1
            value: Audio.source?.audio?.volume ?? 0
            onValueChanged: {
                if (Audio.source?.audio) Audio.source.audio.volume = value;
            }
        }
        ConfigSwitch {
            buttonIcon: "mic_off"
            text: Translation.tr("Mute")
            checked: Audio.source?.audio?.muted ?? false
            onCheckedChanged: {
                if (Audio.source?.audio) Audio.source.audio.muted = checked;
            }
        }

        Repeater {
            model: ScriptModel {
                values: Audio.inputDevices
            }
            delegate: ConfigRow {
                id: inputRow
                required property var modelData
                readonly property var device: inputRow.modelData
                readonly property bool isDefault: inputRow.device?.id === Audio.source?.id

                MaterialSymbol {
                    text: "mic"
                    iconSize: Appearance.font.pixelSize.larger
                    color: inputRow.isDefault ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: inputRow.device ? Audio.friendlyDeviceName(inputRow.device) : Translation.tr("Unknown device")
                    }
                    StyledText {
                        visible: inputRow.isDefault
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Default")
                    }
                }
                RippleButtonWithIcon {
                    visible: !inputRow.isDefault
                    materialIcon: "check"
                    mainText: Translation.tr("Set default")
                    buttonRadius: Appearance.rounding.small
                    onClicked: {
                        Audio.setDefaultSource(inputRow.device);
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "hearing"
        title: Translation.tr("Volume protection")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: {
                Config.options.audio.protection.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Prevents abrupt increments and restricts volume limit")
            }
        }
        ConfigRow {
            enabled: Config.options.audio.protection.enable
            ConfigSpinBox {
                icon: "arrow_warm_up"
                text: Translation.tr("Max allowed increase")
                value: Config.options.audio.protection.maxAllowedIncrease
                from: 0
                to: 100
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowedIncrease = value;
                }
            }
            ConfigSpinBox {
                icon: "vertical_align_top"
                text: Translation.tr("Volume limit")
                value: Config.options.audio.protection.maxAllowed
                from: 0
                to: 154 // pavucontrol allows up to 153%
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowed = value;
                }
            }
        }
    }
}
