import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Power Profile")
    toggled: PowerSaving.profile !== "balanced"
    icon: switch(PowerSaving.profile) {
        case "power-saver": return "energy_savings_leaf"
        case "balanced": return "airwave"
        case "performance": return "local_fire_department"
    }
    statusText: switch(PowerSaving.profile) {
        case "power-saver": return "Power Saver"
        case "balanced": return "Balanced"
        case "performance": return "Performance"
    }

    mainAction: () => {
        if (PowerSaving.hasPerformanceProfile) {
            switch(PowerSaving.profile) {
                case "power-saver": PowerSaving.setProfile("balanced")
                break;
                case "balanced": PowerSaving.setProfile("performance")
                break;
                case "performance": PowerSaving.setProfile("power-saver")
                break;
            }
        } else {
            PowerSaving.setProfile(PowerSaving.profile === "balanced" ? "power-saver" : "balanced")
        }
    }
    tooltipText: Translation.tr("Click to cycle through power profiles")
}
