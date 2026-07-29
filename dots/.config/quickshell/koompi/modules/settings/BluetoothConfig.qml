import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
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
            checked: Bluetooth.defaultAdapter?.enabled ?? false
            onCheckedChanged: {
                BluetoothStatus.setEnabled(checked);
            }
        }
        ConfigSwitch {
            visible: BluetoothStatus.available
            enabled: Bluetooth.defaultAdapter?.enabled ?? false
            buttonIcon: "search"
            text: Translation.tr("Scan for devices")
            checked: Bluetooth.defaultAdapter?.discovering ?? false
            onCheckedChanged: {
                if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = checked;
            }
        }
        StyledIndeterminateProgressBar {
            visible: Bluetooth.defaultAdapter?.discovering ?? false
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
                        text: deviceRow.device?.name || Translation.tr("Unknown device")
                    }
                    StyledText {
                        visible: deviceRow.device?.paired ?? false
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: {
                            let statusText = deviceRow.device?.connected ? Translation.tr("Connected") : Translation.tr("Paired");
                            if (deviceRow.device?.batteryAvailable)
                                statusText += ` • ${Math.round(deviceRow.device.battery * 100)}%`;
                            return statusText;
                        }
                    }
                }
                RippleButtonWithIcon {
                    materialIcon: deviceRow.device?.connected ? "link_off" : "link"
                    mainText: deviceRow.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                    buttonRadius: Appearance.rounding.small
                    onClicked: {
                        if (deviceRow.device?.connected) deviceRow.device.disconnect();
                        else deviceRow.device?.connect();
                    }
                }
                RippleButtonWithIcon {
                    materialIcon: deviceRow.device?.paired ? "delete" : "handshake"
                    mainText: deviceRow.device?.paired ? Translation.tr("Forget") : Translation.tr("Pair")
                    buttonRadius: Appearance.rounding.small
                    onClicked: {
                        if (deviceRow.device?.paired) deviceRow.device.forget();
                        else deviceRow.device?.pair();
                    }
                }
            }
        }
    }
}
