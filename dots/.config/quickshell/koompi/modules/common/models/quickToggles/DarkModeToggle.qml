import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    property bool auto: DarkMode.automatic

    name: Translation.tr("Dark Mode")
    statusText: (auto ? Translation.tr("Auto, ") : "") + (DarkMode.dark ? Translation.tr("Dark") : Translation.tr("Light"))

    toggled: DarkMode.dark
    icon: auto ? "brightness_auto" : "contrast"

    mainAction: () => {
        DarkMode.toggle();
    }
    altAction: () => {
        DarkMode.setAutomatic(!DarkMode.automatic);
    }

    tooltipText: Translation.tr("Dark Mode | Right-click for sunset to sunrise")
}
