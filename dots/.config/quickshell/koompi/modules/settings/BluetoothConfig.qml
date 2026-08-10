import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "bluetooth"
        title: Translation.tr("Bluetooth")

        StyledText {
            visible: !BluetoothStatus.available
            text: Translation.tr("No Bluetooth adapter found")
            color: Appearance.colors.colSubtext
        }

        ConfigSwitch {
            visible: BluetoothStatus.available
            buttonIcon: "bluetooth"
            text: Translation.tr("Enable Bluetooth")
            checked: BluetoothStatus.enabled
            onCheckedChanged: {
                BluetoothStatus.setEnabled(checked);
            }
        }
        ConfigSwitch {
            visible: BluetoothStatus.available
            enabled: BluetoothStatus.enabled
            buttonIcon: "search"
            text: Translation.tr("Scan for devices")
            checked: BluetoothStatus.discovering
            onCheckedChanged: {
                BluetoothStatus.setDiscovering(checked);
            }
        }
        StyledIndeterminateProgressBar {
            visible: BluetoothStatus.discovering
            Layout.fillWidth: true
        }
    }

    ContentSection {
        icon: "devices_other"
        title: Translation.tr("Devices")
        visible: BluetoothStatus.available

        StyledText {
            visible: BluetoothStatus.friendlyDeviceList.length === 0
            text: Translation.tr("No devices. Turn on scanning to find nearby devices.")
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: ScriptModel {
                values: BluetoothStatus.friendlyDeviceList
            }
            delegate: ConfigRow {
                id: deviceRow
                required property var modelData
                readonly property var device: deviceRow.modelData

                MaterialSymbol {
                    text: "bluetooth"
                    iconSize: Appearance.font.pixelSize.larger
                    color: deviceRow.device?.connected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                }
                ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: deviceRow.device?.alias || Translation.tr("Unknown device")
                    }
                    StyledText {
                        visible: deviceRow.device?.paired ?? false
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: {
                            let statusText = deviceRow.device?.connected ? Translation.tr("Connected") : Translation.tr("Paired");
                            if (deviceRow.device?.battery != null)
                                statusText += ` • ${deviceRow.device.battery}%`;
                            return statusText;
                        }
                    }
                }
                RippleButtonWithIcon {
                    materialIcon: deviceRow.device?.connected ? "link_off" : "link"
                    mainText: deviceRow.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                    buttonRadius: Appearance.rounding.small
                    onClicked: {
                        if (deviceRow.device?.connected) BluetoothStatus.disconnectDevice(deviceRow.device);
                        else BluetoothStatus.connectDevice(deviceRow.device);
                    }
                }
                RippleButtonWithIcon {
                    materialIcon: deviceRow.device?.paired ? "delete" : "handshake"
                    mainText: deviceRow.device?.paired ? Translation.tr("Forget") : Translation.tr("Pair")
                    buttonRadius: Appearance.rounding.small
                    onClicked: {
                        if (deviceRow.device?.paired) BluetoothStatus.forget(deviceRow.device);
                        else BluetoothStatus.pair(deviceRow.device);
                    }
                }
            }
        }
    }
}
