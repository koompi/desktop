import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "call_to_action"
    title: Translation.tr("Dock")

    ConfigSwitch {
        buttonIcon: "check"
        text: Translation.tr("Enable")
        checked: Config.options.dock.enable
        onCheckedChanged: {
            Config.options.dock.enable = checked;
        }
    }

    ConfigRow {
        uniform: true
        ConfigSwitch {
            buttonIcon: "highlight_mouse_cursor"
            text: Translation.tr("Hover to reveal")
            checked: Config.options.dock.hoverToReveal
            onCheckedChanged: {
                Config.options.dock.hoverToReveal = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr("Pinned on startup")
            checked: Config.options.dock.pinnedOnStartup
            onCheckedChanged: {
                Config.options.dock.pinnedOnStartup = checked;
            }
        }
    }
    ConfigSwitch {
        buttonIcon: "colors"
        text: Translation.tr("Tint app icons")
        checked: Config.options.dock.monochromeIcons
        onCheckedChanged: {
            Config.options.dock.monochromeIcons = checked;
        }
    }
}
