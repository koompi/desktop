import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "person"
        title: Translation.tr("Account")

        RowLayout {
            spacing: 16

            // ~/.face is the de-facto avatar convention; fall back to an icon.
            Item {
                implicitWidth: 64
                implicitHeight: 64
                Image {
                    id: faceImage
                    anchors.fill: parent
                    source: `file://${Directories.home.replace("file://", "")}/.face`
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: faceImage.width
                            height: faceImage.height
                            radius: width / 2
                        }
                    }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: faceImage.status !== Image.Ready
                    text: "account_circle"
                    iconSize: 64
                    color: Appearance.colors.colOnLayer1
                }
            }
            ColumnLayout {
                spacing: 2
                StyledText {
                    text: SystemInfo.username
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                }
                StyledText {
                    text: `${SystemInfo.username}@${SystemInfo.hostname}`
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    ContentSection {
        icon: "key"
        title: Translation.tr("Security")

        ConfigRow {
            RippleButtonWithIcon {
                materialIcon: "password"
                mainText: Translation.tr("Change password")
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.changePassword]);
                }
                StyledToolTip {
                    text: Translation.tr("Opens a terminal running passwd")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "person_add"
                mainText: Translation.tr("Add user")
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    Quickshell.execDetached(["bash", "-c", Config.options.apps.addUser]);
                }
                StyledToolTip {
                    text: Translation.tr("Create a new user account (asks for admin rights)")
                }
            }
        }
    }
}
