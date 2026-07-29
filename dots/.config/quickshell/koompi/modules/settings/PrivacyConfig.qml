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

    property string defaultBackends: "hyprland;gtk"
    property string fileChooserBackend: "gtk"
    readonly property string screencastBackend: root.defaultBackends.split(";")[0] ?? ""

    FileView {
        id: portalConfFile
        path: `${FileUtils.trimFileProtocol(Directories.config)}/xdg-desktop-portal/koompi-portals.conf`
        onLoaded: {
            const lines = portalConfFile.text().split("\n");
            for (const line of lines) {
                const match = line.match(/^\s*([^#=\s][^=]*?)\s*=\s*(.+?)\s*$/);
                if (!match)
                    continue;
                if (match[1] === "default")
                    root.defaultBackends = match[2];
                else if (match[1].endsWith(".FileChooser"))
                    root.fileChooserBackend = match[2];
            }
        }
    }

    ContentSection {
        icon: "sensors"
        title: Translation.tr("Active sensors")

        ConfigRow {
            MaterialSymbol {
                text: "screen_share"
                iconSize: Appearance.font.pixelSize.larger
                color: Privacy?.screenSharing ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Screen sharing")
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Privacy?.screenSharing ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                text: Privacy?.screenSharing ? Translation.tr("Active") : Translation.tr("Not in use")
            }
        }
        ConfigRow {
            MaterialSymbol {
                text: "mic"
                iconSize: Appearance.font.pixelSize.larger
                color: Privacy?.micActive ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Microphone")
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Privacy?.micActive ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                text: Privacy?.micActive ? Translation.tr("Active") : Translation.tr("Not in use")
            }
        }
    }

    ContentSection {
        icon: "policy"
        title: Translation.tr("Content policies")

        ColumnLayout {
            spacing: 0
            ConfigSwitch {
                buttonIcon: "neurology"
                text: Translation.tr("AI features")
                checked: (Config.options?.policies?.ai ?? 0) !== 0
                onCheckedChanged: {
                    Config.options.policies.ai = checked ? 1 : 0;
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 40
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Allows AI assistant features in the shell")
            }
        }
        ColumnLayout {
            spacing: 0
            ConfigSwitch {
                buttonIcon: "sentiment_very_satisfied"
                text: Translation.tr("Weeb content")
                checked: (Config.options?.policies?.weeb ?? 0) !== 0
                onCheckedChanged: {
                    Config.options.policies.weeb = checked ? 1 : 0;
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 40
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("Toggles anime content sources in the shell")
            }
        }
    }

    ContentSection {
        icon: "door_open"
        title: Translation.tr("Portals")

        ConfigRow {
            MaterialSymbol {
                text: "present_to_all"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("ScreenCast & Screenshot")
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Handled by %1").arg(root.screencastBackend)
                }
            }
        }
        ConfigRow {
            MaterialSymbol {
                text: "folder_open"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("FileChooser")
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Handled by %1").arg(root.fileChooserBackend)
                }
            }
        }
        ConfigRow {
            MaterialSymbol {
                text: "sort"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Backend preference order")
                }
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: root.defaultBackends
                }
            }
        }
    }
}
