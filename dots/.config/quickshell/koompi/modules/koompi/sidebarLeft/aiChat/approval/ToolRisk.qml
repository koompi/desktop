pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell
import QtQuick

/**
 * What a `risk` from `Ai.riskOf` means on screen. A local read, a change to this
 * machine and something that leaves it are three colours and three sentences, so
 * the user can tell them apart without reading the command.
 */
Singleton {
    id: root

    function icon(risk: string): string {
        switch (risk) {
        case "safe": return "lock";
        case "reads-system": return "visibility";
        case "leaves-machine": return "cloud_upload";
        default: return "edit_note";
        }
    }

    function label(risk: string): string {
        switch (risk) {
        case "safe": return Translation.tr("Stays local");
        case "reads-system": return Translation.tr("Reads this machine");
        case "leaves-machine": return Translation.tr("Leaves this machine");
        default: return Translation.tr("Changes this machine");
        }
    }

    function sentence(risk: string): string {
        switch (risk) {
        case "safe": return Translation.tr("This action stays on your device and changes nothing on it.");
        case "reads-system": return Translation.tr("This reads your machine. Nothing is changed and no data leaves the device.");
        case "leaves-machine": return Translation.tr("This sends what you ask, and anything it reads here, to a service off this machine.");
        default: return Translation.tr("This runs on your machine and can change it. No data leaves the device.");
        }
    }

    function accent(risk: string): color {
        switch (risk) {
        case "safe":
        case "reads-system": return Appearance.colors.colOnTertiaryContainer;
        case "leaves-machine": return Appearance.colors.colOnErrorContainer;
        default: return Appearance.colors.colOnSecondaryContainer;
        }
    }

    function container(risk: string): color {
        switch (risk) {
        case "safe":
        case "reads-system": return Appearance.colors.colTertiaryContainer;
        case "leaves-machine": return Appearance.colors.colErrorContainer;
        default: return Appearance.colors.colSecondaryContainer;
        }
    }
}
