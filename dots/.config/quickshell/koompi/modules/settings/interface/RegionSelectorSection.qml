import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "screenshot_frame_2"
    title: Translation.tr("Region selector (screen snipping/Google Lens)")

    ContentSubsection {
        title: Translation.tr("Hint target regions")
        ConfigRow {
            ConfigSwitch {
                buttonIcon: "select_window"
                text: Translation.tr('Windows')
                checked: Config.options.regionSelector.targetRegions.windows
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.windows = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "right_panel_open"
                text: Translation.tr('Layers')
                checked: Config.options.regionSelector.targetRegions.layers
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.layers = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "nearby"
                text: Translation.tr('Content')
                checked: Config.options.regionSelector.targetRegions.content
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.content = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Could be images or parts of the screen that have some containment.\nMight not always be accurate.\nThis is done with an image processing algorithm run locally and no AI is used.")
                }
            }
        }
    }
    
    ContentSubsection {
        title: Translation.tr("Google Lens")
        
        ConfigSelectionArray {
            currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
            onSelected: newValue => {
                Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
            }
            options: [
                { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
            ]
        }
    }

    ContentSubsection {
        title: Translation.tr("Rectangular selection")

        ConfigSwitch {
            buttonIcon: "point_scan"
            text: Translation.tr("Show aim lines")
            checked: Config.options.regionSelector.rect.showAimLines
            onCheckedChanged: {
                Config.options.regionSelector.rect.showAimLines = checked;
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Circle selection")
        
        ConfigSpinBox {
            icon: "eraser_size_3"
            text: Translation.tr("Stroke width")
            value: Config.options.regionSelector.circle.strokeWidth
            from: 1
            to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.regionSelector.circle.strokeWidth = value;
            }
        }

        ConfigSpinBox {
            icon: "screenshot_frame_2"
            text: Translation.tr("Padding")
            value: Config.options.regionSelector.circle.padding
            from: 0
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.regionSelector.circle.padding = value;
            }
        }
    }
}
