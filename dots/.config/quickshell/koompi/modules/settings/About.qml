import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "box"
        title: Translation.tr("Distro")
        
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 20
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            IconImage {
                implicitSize: 80
                // KOOMPI logo is theme-adaptive: white on dark, navy on light
                source: Quickshell.iconPath(Appearance.m3colors.darkmode ? "koompi" : "koompi-light")
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                // spacing: 10
                StyledText {
                    text: SystemInfo.distroName
                    font.pixelSize: Appearance.font.pixelSize.title
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.normal
                    text: SystemInfo.homeUrl
                    textFormat: Text.MarkdownText
                    onLinkActivated: (link) => {
                        Qt.openUrlExternally(link)
                    }
                    PointingHandLinkHover {}
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5

            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.documentationUrl)
                }
            }
            RippleButtonWithIcon {
                materialIcon: "support"
                mainText: Translation.tr("Help & Support")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.supportUrl)
                }
            }
            RippleButtonWithIcon {
                materialIcon: "bug_report"
                mainText: Translation.tr("Report a Bug")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.bugReportUrl)
                }
            }
            RippleButtonWithIcon {
                materialIcon: "policy"
                materialIconFill: false
                mainText: Translation.tr("Privacy Policy")
                onClicked: {
                    Qt.openUrlExternally(SystemInfo.privacyPolicyUrl)
                }
            }
            
        }

    }
    ContentSection {
        icon: "folder_managed"
        title: Translation.tr("Desktop")

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 4
            StyledText {
                text: Translation.tr("Hyprland desktop, part of KOOMPI OS")
                font.pixelSize: Appearance.font.pixelSize.normal
            }
            StyledText {
                text: "https://github.com/rithythul/koompi-desktop"
                font.pixelSize: Appearance.font.pixelSize.normal
                textFormat: Text.MarkdownText
                onLinkActivated: (link) => {
                    Qt.openUrlExternally(link)
                }
                PointingHandLinkHover {}
            }
            StyledText {
                text: "Based on [illogical-impulse](https://github.com/end-4/dots-hyprland) by end-4"
                font.pixelSize: Appearance.font.pixelSize.smaller
                textFormat: Text.MarkdownText
                onLinkActivated: (link) => {
                    Qt.openUrlExternally(link)
                }
                PointingHandLinkHover {}
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 5

            RippleButtonWithIcon {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: {
                    Qt.openUrlExternally("https://github.com/rithythul/koompi-desktop")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "adjust"
                materialIconFill: false
                mainText: Translation.tr("Issues")
                onClicked: {
                    Qt.openUrlExternally("https://github.com/rithythul/koompi-desktop/issues")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "forum"
                mainText: Translation.tr("Discussions")
                onClicked: {
                    Qt.openUrlExternally("https://github.com/rithythul/koompi-desktop/discussions")
                }
            }
            RippleButtonWithIcon {
                materialIcon: "favorite"
                mainText: Translation.tr("Support end-4")
                onClicked: {
                    Qt.openUrlExternally("https://github.com/sponsors/end-4")
                }
            }

            
        }
    }
}
