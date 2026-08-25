import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "wallpaper_slideshow"
    title: Translation.tr("Wallpaper selector")

    ConfigSwitch {
        buttonIcon: "ad"
        text: Translation.tr('Use system file picker')
        checked: Config.options.wallpaperSelector.useSystemFileDialog
        onCheckedChanged: {
            Config.options.wallpaperSelector.useSystemFileDialog = checked;
        }
    }
}
