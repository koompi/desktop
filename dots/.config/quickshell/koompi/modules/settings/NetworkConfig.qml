import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "wifi"
        title: Translation.tr("Wi-Fi")

        ConfigSwitch {
            buttonIcon: "wifi"
            text: Translation.tr("Enable Wi-Fi")
            checked: Network.wifiEnabled
            onCheckedChanged: {
                Network.enableWifi(checked);
            }
        }
        RippleButtonWithIcon {
            enabled: Network.wifiEnabled && !Network.wifiScanning
            materialIcon: "refresh"
            mainText: Network.wifiScanning ? Translation.tr("Scanning...") : Translation.tr("Rescan networks")
            onClicked: {
                Network.rescanWifi();
            }
        }
        StyledIndeterminateProgressBar {
            visible: Network.wifiScanning
            Layout.fillWidth: true
        }

        StyledText {
            visible: Network.wifiEnabled && Network.friendlyWifiNetworks.length === 0
            text: Translation.tr("No networks found. Try rescanning.")
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: ScriptModel {
                values: Network.friendlyWifiNetworks
            }
            delegate: ColumnLayout {
                id: networkRow
                required property var modelData
                readonly property var network: networkRow.modelData
                Layout.fillWidth: true
                spacing: 0

                ConfigRow {
                    MaterialSymbol {
                        property int strength: networkRow.network?.strength ?? 0
                        text: strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar" : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
                        iconSize: Appearance.font.pixelSize.larger
                        color: networkRow.network?.active ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            text: networkRow.network?.ssid || Translation.tr("Unknown network")
                        }
                        StyledText {
                            visible: (networkRow.network?.active || Network.wifiConnectTarget === networkRow.network) ?? false
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: networkRow.network?.active ? Translation.tr("Connected") : Translation.tr("Connecting...")
                        }
                    }
                    MaterialSymbol {
                        visible: networkRow.network?.isSecure ?? false
                        text: "lock"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colSubtext
                    }
                    RippleButtonWithIcon {
                        enabled: !(Network.wifiConnectTarget === networkRow.network && !networkRow.network?.active)
                        materialIcon: networkRow.network?.active ? "link_off" : "link"
                        mainText: networkRow.network?.active ? Translation.tr("Disconnect") : Translation.tr("Connect")
                        buttonRadius: Appearance.rounding.small
                        onClicked: {
                            if (networkRow.network?.active) Network.disconnectWifiNetwork();
                            else Network.connectToWifiNetwork(networkRow.network);
                        }
                    }
                }

                ColumnLayout { // Password
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    visible: networkRow.network?.askingPassword ?? false

                    MaterialTextField {
                        id: passwordField
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Password")

                        // Password
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData

                        onAccepted: {
                            Network.changePassword(networkRow.network, passwordField.text);
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Item {
                            Layout.fillWidth: true
                        }

                        DialogButton {
                            buttonText: Translation.tr("Cancel")
                            onClicked: {
                                if (networkRow.network) networkRow.network.askingPassword = false;
                            }
                        }

                        DialogButton {
                            buttonText: Translation.tr("Connect")
                            onClicked: {
                                Network.changePassword(networkRow.network, passwordField.text);
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "lan"
        title: Translation.tr("Ethernet")

        ConfigRow {
            MaterialSymbol {
                text: "lan"
                iconSize: Appearance.font.pixelSize.larger
                color: Network.ethernet ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: Network.ethernet ? (Network.networkName || Translation.tr("Wired connection")) : Translation.tr("No wired connection")
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Network.ethernet ? (Network.connected ? Translation.tr("Connected") : Translation.tr("Limited connectivity")) : Translation.tr("Cable unplugged or adapter unavailable")
                }
            }
        }
        RippleButtonWithIcon {
            materialIcon: "settings_ethernet"
            mainText: Translation.tr("Advanced configuration")
            onClicked: {
                Quickshell.execDetached(["nm-connection-editor"]);
            }
        }
    }
}
