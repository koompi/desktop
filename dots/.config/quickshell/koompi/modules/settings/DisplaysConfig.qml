import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property var hyprMonitors: ({})
    readonly property string anchorName: {
        const screens = [...Quickshell.screens];
        return (screens.find(s => s.name?.startsWith("eDP")) ?? screens[0])?.name ?? "";
    }

    Component.onCompleted: {
        Hyprsunset.fetchState();
    }

    Timer {
        id: monitorsRefreshTimer
        interval: 1200
        onTriggered: {
            monitorsProc.running = false;
            monitorsProc.running = true;
        }
    }

    Process {
        id: monitorsProc
        running: true
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                const parsed = JSON.parse(monitorsCollector.text);
                const map = {};
                for (const monitor of parsed) map[monitor.name] = monitor;
                root.hyprMonitors = map;
            }
        }
    }

    ContentSection {
        icon: "monitor"
        title: Translation.tr("Monitors")

        StyledText {
            visible: Quickshell.screens.length === 0
            text: Translation.tr("No monitors found")
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: ScriptModel {
                values: [...Quickshell.screens]
            }
            delegate: ColumnLayout {
                id: monitorBlock
                required property var modelData
                readonly property var screenInfo: monitorBlock.modelData
                readonly property var hyprInfo: root.hyprMonitors[monitorBlock.screenInfo?.name ?? ""]
                readonly property var brightnessMonitor: Brightness.getMonitorForScreen(monitorBlock.screenInfo)
                readonly property string relativePosition: {
                    const a = root.hyprMonitors[root.anchorName];
                    const m = monitorBlock.hyprInfo;
                    if (!a || !m) return "";
                    if (m.x + m.width / m.scale <= a.x) return "left";
                    if (m.x >= a.x + a.width / a.scale) return "right";
                    if (m.y < a.y) return "above";
                    return "below";
                }

                spacing: 4
                Layout.fillWidth: true

                ConfigRow {
                    MaterialSymbol {
                        text: "monitor"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: {
                                const name = monitorBlock.screenInfo?.name ?? Translation.tr("Unknown monitor");
                                const model = monitorBlock.screenInfo?.model;
                                return model ? `${name} • ${model}` : name;
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: {
                                const details = [];
                                const width = monitorBlock.screenInfo?.width ?? 0;
                                const height = monitorBlock.screenInfo?.height ?? 0;
                                const refreshRate = monitorBlock.hyprInfo?.refreshRate;
                                details.push(refreshRate !== undefined ? `${width}x${height}@${Math.round(refreshRate)}Hz` : `${width}x${height}`);
                                const scale = monitorBlock.hyprInfo?.scale;
                                if (scale !== undefined)
                                    details.push(Translation.tr("Scale %1").arg(scale));
                                const x = monitorBlock.hyprInfo?.x;
                                const y = monitorBlock.hyprInfo?.y;
                                if (x !== undefined && y !== undefined)
                                    details.push(Translation.tr("Position %1, %2").arg(x).arg(y));
                                return details.join(" • ");
                            }
                        }
                    }
                }
                ConfigSlider {
                    text: Translation.tr("Brightness")
                    buttonIcon: "brightness_6"
                    from: 0
                    to: 1
                    value: monitorBlock.brightnessMonitor?.brightness ?? 0
                    onValueChanged: {
                        monitorBlock.brightnessMonitor?.setBrightness(value);
                    }
                }
                StyledText {
                    visible: monitorBlock.brightnessMonitor?.isDdc ?? false
                    Layout.leftMargin: 8
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("External monitor controlled via DDC/CI")
                }
                ContentSubsection {
                    visible: monitorBlock.screenInfo?.name !== root.anchorName && [...Quickshell.screens].length > 1
                    title: Translation.tr("Position relative to %1").arg(root.anchorName)
                    ConfigSelectionArray {
                        currentValue: monitorBlock.relativePosition
                        options: [
                            { displayName: Translation.tr("Left of"), icon: "arrow_back", value: "left" },
                            { displayName: Translation.tr("Right of"), icon: "arrow_forward", value: "right" },
                            { displayName: Translation.tr("Above"), icon: "arrow_upward", value: "above" },
                            { displayName: Translation.tr("Below"), icon: "arrow_downward", value: "below" }
                        ]
                        onSelected: newValue => {
                            // Absolute path: the session env may lack ~/.local/bin on PATH
                            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/koompi-displays", "place", monitorBlock.screenInfo?.name ?? "", newValue]);
                            monitorsRefreshTimer.restart();
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "nightlight"
        title: Translation.tr("Night light")

        ConfigSwitch {
            buttonIcon: "bedtime"
            text: Translation.tr("Enable night light")
            checked: Hyprsunset.temperatureActive
            onCheckedChanged: {
                if (checked !== Hyprsunset.temperatureActive)
                    Hyprsunset.toggleTemperature(checked);
            }
        }
        ConfigSwitch {
            buttonIcon: "night_sight_auto"
            text: Translation.tr("Automatic schedule")
            checked: Config.options?.light?.night?.automatic ?? false
            onCheckedChanged: {
                Config.options.light.night.automatic = checked;
            }
        }
        ConfigSlider {
            text: Translation.tr("Color temperature")
            buttonIcon: "thermostat"
            usePercentTooltip: false
            from: 1000
            to: 6500
            value: Config.options?.light?.night?.colorTemperature ?? 5000
            onValueChanged: {
                Config.options.light.night.colorTemperature = Math.round(value);
            }
        }
        ConfigSlider {
            text: Translation.tr("Gamma")
            buttonIcon: "brightness_medium"
            from: Hyprsunset.gammaLowerLimit
            to: 100
            value: Hyprsunset.gamma
            onValueChanged: {
                if (Math.round(value) !== Hyprsunset.gamma)
                    Hyprsunset.setGamma(Math.round(value));
            }
        }
    }
}
