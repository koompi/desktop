import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "text_format"
    title: Translation.tr("Fonts")

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
