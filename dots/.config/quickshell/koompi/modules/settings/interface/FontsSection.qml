import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "text_format"
    title: Translation.tr("Fonts")

    ContentSubsection {
        title: Translation.tr("Text size")
        tooltip: Translation.tr("One size for the shell, GTK apps and the terminal, in px. 16 is the shipped size.")

        RowLayout {
            spacing: 10
            Layout.leftMargin: 8
            Layout.rightMargin: 8

            StyledText {
                Layout.preferredWidth: 48
                text: `${Math.round(textSizeSlider.value)} px`
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledSlider {
                id: textSizeSlider
                Layout.fillWidth: true
                configuration: StyledSlider.Configuration.XS
                usePercentTooltip: false
                from: 9
                to: 24
                stepSize: 1
                snapMode: Slider.SnapAlways
                // Dragging would break a plain `value:` binding; this one survives
                // it, so `koompi-theme text-size` run from a terminal moves the knob too.
                Binding on value {
                    value: Config.options.appearance.fonts.baseSize
                }
                onMoved: textSizeApply.restart()
            }
        }
        // The tool owns the side effects (config key, GTK factor, terminal
        // size, hook); the shell reflows when config.json comes back through
        // Config's file watch. One run per settled drag, not one per step.
        Timer {
            id: textSizeApply
            interval: Appearance.animationDuration.normal
            onTriggered: Quickshell.execDetached(["koompi-theme", "text-size", String(Math.round(textSizeSlider.value))])
        }
    }

    ContentSubsection {
        title: Translation.tr("Main font")
        tooltip: Translation.tr("Used for general UI text")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Font family name (e.g., Google Sans Flex)")
            text: Config.options.appearance.fonts.main
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.appearance.fonts.main = text;
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Numbers font")
        tooltip: Translation.tr("Used for displaying numbers")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Font family name")
            text: Config.options.appearance.fonts.numbers
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.appearance.fonts.numbers = text;
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Title font")
        tooltip: Translation.tr("Used for headings and titles")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Font family name")
            text: Config.options.appearance.fonts.title
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.appearance.fonts.title = text;
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Monospace font")
        tooltip: Translation.tr("Used for code and terminal")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Font family name (e.g., JetBrains Mono NF)")
            text: Config.options.appearance.fonts.monospace
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.appearance.fonts.monospace = text;
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Nerd font icons")
        tooltip: Translation.tr("Font used for Nerd Font icons")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Font family name (e.g., JetBrains Mono NF)")
            text: Config.options.appearance.fonts.iconNerd
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.appearance.fonts.iconNerd = text;
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Reading font")
        tooltip: Translation.tr("Used for reading large blocks of text")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Font family name (e.g., Readex Pro)")
            text: Config.options.appearance.fonts.reading
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.appearance.fonts.reading = text;
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Expressive font")
        tooltip: Translation.tr("Used for decorative/expressive text")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Font family name (e.g., Space Grotesk)")
            text: Config.options.appearance.fonts.expressive
            wrapMode: TextEdit.NoWrap
            onTextChanged: {
                Config.options.appearance.fonts.expressive = text;
            }
        }
    }
}
