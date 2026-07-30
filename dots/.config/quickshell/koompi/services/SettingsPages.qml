pragma Singleton

import qs.modules.common
import Quickshell

/**
 * The KOOMPI Settings page list, shared by the settings window and by Search
 * so the two cannot drift apart.
 */
Singleton {
    id: root

    readonly property var list: [
        {
            name: Translation.tr("Quick"),
            icon: "instant_mix",
            component: "modules/settings/QuickConfig.qml"
        },
        {
            name: Translation.tr("General"),
            icon: "browse",
            component: "modules/settings/GeneralConfig.qml"
        },
        {
            name: Translation.tr("Bar"),
            icon: "toast",
            iconRotation: 180,
            component: "modules/settings/BarConfig.qml"
        },
        {
            name: Translation.tr("Background"),
            icon: "texture",
            component: "modules/settings/BackgroundConfig.qml"
        },
        {
            name: Translation.tr("Interface"),
            icon: "bottom_app_bar",
            component: "modules/settings/InterfaceConfig.qml"
        },
        {
            name: Translation.tr("Displays"),
            icon: "monitor",
            component: "modules/settings/DisplaysConfig.qml"
        },
        {
            name: Translation.tr("Input"),
            icon: "keyboard",
            component: "modules/settings/InputConfig.qml"
        },
        {
            name: Translation.tr("Shortcuts"),
            icon: "keyboard_command_key",
            component: "modules/settings/ShortcutsConfig.qml"
        },
        {
            name: Translation.tr("Network"),
            icon: "wifi",
            component: "modules/settings/NetworkConfig.qml"
        },
        {
            name: Translation.tr("Bluetooth"),
            icon: "bluetooth",
            component: "modules/settings/BluetoothConfig.qml"
        },
        {
            name: Translation.tr("Sound"),
            icon: "volume_up",
            component: "modules/settings/SoundConfig.qml"
        },
        {
            name: Translation.tr("Power"),
            icon: "battery_full",
            component: "modules/settings/PowerConfig.qml"
        },
        {
            name: Translation.tr("Privacy"),
            icon: "shield_person",
            component: "modules/settings/PrivacyConfig.qml"
        },
        {
            name: Translation.tr("Account"),
            icon: "person",
            component: "modules/settings/AccountConfig.qml"
        },
        {
            name: Translation.tr("Services"),
            icon: "settings",
            component: "modules/settings/ServicesConfig.qml"
        },
        {
            name: Translation.tr("Advanced"),
            icon: "construction",
            component: "modules/settings/AdvancedConfig.qml"
        },
        {
            name: Translation.tr("About"),
            icon: "info",
            component: "modules/settings/About.qml"
        }
    ]

    // The argument `koompi-settings` takes, derived from the component filename
    // the same way settings.qml matches KOOMPI_SETTINGS_PAGE against it.
    function pageArg(page) {
        return page.component.slice(page.component.lastIndexOf("/") + 1).replace(/(Config)?\.qml$/, "").toLowerCase();
    }

    function open(page) {
        Quickshell.execDetached(["bash", "-c", `~/.local/bin/koompi-settings ${root.pageArg(page)}`]);
    }
}
