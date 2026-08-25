import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "overview_key"
    title: Translation.tr("Overview")

    ConfigSwitch {
        buttonIcon: "check"
        text: Translation.tr("Enable")
        checked: Config.options.overview.enable
        onCheckedChanged: {
            Config.options.overview.enable = checked;
        }
    }
    ConfigSwitch {
        buttonIcon: "center_focus_strong"
        text: Translation.tr("Center icons")
        checked: Config.options.overview.centerIcons
        onCheckedChanged: {
            Config.options.overview.centerIcons = checked;
        }
    }
    ConfigSpinBox {
        icon: "loupe"
        text: Translation.tr("Scale (%)")
        value: Config.options.overview.scale * 100
        from: 1
        to: 100
        stepSize: 1
        onValueChanged: {
            Config.options.overview.scale = value / 100;
        }
    }
    ConfigRow {
        uniform: true
        ConfigSpinBox {
            icon: "splitscreen_bottom"
            text: Translation.tr("Rows")
            value: Config.options.overview.rows
            from: 1
            to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.overview.rows = value;
            }
        }
        ConfigSpinBox {
            icon: "splitscreen_right"
            text: Translation.tr("Columns")
            value: Config.options.overview.columns
            from: 1
            to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.overview.columns = value;
            }
        }
    }
    ConfigRow {
        uniform: true
        ConfigSelectionArray {
            currentValue: Config.options.overview.orderRightLeft
            onSelected: newValue => {
                Config.options.overview.orderRightLeft = newValue
            }
            options: [
                {
                    displayName: Translation.tr("Left to right"),
                    icon: "arrow_forward",
                    value: 0
                },
                {
                    displayName: Translation.tr("Right to left"),
                    icon: "arrow_back",
                    value: 1
                }
            ]
        }
        ConfigSelectionArray {
            currentValue: Config.options.overview.orderBottomUp
            onSelected: newValue => {
                Config.options.overview.orderBottomUp = newValue
            }
            options: [
                {
                    displayName: Translation.tr("Top-down"),
                    icon: "arrow_downward",
                    value: 0
                },
                {
                    displayName: Translation.tr("Bottom-up"),
                    icon: "arrow_upward",
                    value: 1
                }
            ]
        }
    }
}
