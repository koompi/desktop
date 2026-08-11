import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings > AI. Everything the sidebar assistant reads, in the one place a
 * person can find it, instead of behind slash commands typed into a chat.
 *
 * Model, endpoint and temperature live in `Persistent.states.ai.*` rather than
 * `Config.options.ai.*`, because that is where the engine reads them.
 */
ContentPage {
    id: root
    forceWidth: true

    // Only "local" and "remote" are slots. Anything else in the state file is a
    // stale model id that the engine migrates to "remote" on its next start, so
    // show what the engine will show rather than the raw string. Policy 2 is
    // local-only and leaves no remote slot at all.
    readonly property bool remoteAllowed: Config.options.policies.ai !== 2
    readonly property string modelSlot: !root.remoteAllowed ? "local"
        : (Persistent.states.ai.model === "local" ? "local" : "remote")
    readonly property bool localModel: root.modelSlot === "local"

    ContentSection {
        icon: "neurology"
        title: Translation.tr("Model")

        ConfigSelectionArray {
            visible: root.remoteAllowed
            currentValue: root.modelSlot
            onSelected: newValue => {
                Persistent.states.ai.model = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("On this machine"),
                    icon: "sync_saved_locally",
                    value: "local"
                },
                {
                    displayName: Translation.tr("Remote"),
                    icon: "cloud",
                    value: "remote"
                }
            ]
        }

        ContentSubsection {
            title: Translation.tr("Local model")
            tooltip: Translation.tr("LiteRT-LM serves one request at a time on 127.0.0.1:9379.\nRun 'litert-lm list' for the model names it has on disk.")
            visible: root.localModel

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Model name, e.g. gemma4-e4b")
                    text: Persistent.states.ai.localModel
                    onTextChanged: Persistent.states.ai.localModel = text
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Endpoint")
                    text: Persistent.states.ai.localEndpoint
                    onTextChanged: Persistent.states.ai.localEndpoint = text
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Remote model")
            tooltip: Translation.tr("Type /key in the sidebar to store the API key; it goes to the keyring, never here.")
            visible: !root.localModel

            ConfigRow {
                uniform: true
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Model name")
                    text: Persistent.states.ai.remoteModel
                    onTextChanged: Persistent.states.ai.remoteModel = text
                }
                MaterialTextArea {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Endpoint (blank for the model's own)")
                    text: Persistent.states.ai.remoteEndpoint
                    onTextChanged: Persistent.states.ai.remoteEndpoint = text
                }
            }
            ConfigSelectionArray {
                currentValue: Persistent.states.ai.remoteFormat
                onSelected: newValue => {
                    Persistent.states.ai.remoteFormat = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Inferred"),
                        value: ""
                    },
                    {
                        displayName: Translation.tr("OpenAI"),
                        value: "openai"
                    },
                    {
                        displayName: Translation.tr("Gemini"),
                        value: "gemini"
                    },
                    {
                        displayName: Translation.tr("Mistral"),
                        value: "mistral"
                    }
                ]
            }
        }

        ConfigSlider {
            buttonIcon: "thermostat"
            text: Translation.tr("Temperature")
            value: Persistent.states.ai.temperature
            from: 0
            to: 1
            onValueChanged: {
                Persistent.states.ai.temperature = value;
            }
        }

        ContentSubsection {
            title: Translation.tr("Request deadline")
            tooltip: Translation.tr("Past this the request is killed and the model's slot freed.\nA hung request blocks every other one on this machine.")

            ConfigSpinBox {
                icon: "timer_off"
                text: Translation.tr("Give up on a reply after (s)")
                value: Config.options.ai.requestTimeoutSec
                from: 10
                to: 900
                stepSize: 10
                onValueChanged: {
                    Config.options.ai.requestTimeoutSec = value;
                }
            }
        }
    }

    ContentSection {
        icon: "handyman"
        title: Translation.tr("Tools")

        ContentSubsection {
            title: Translation.tr("What the model may call")

            ConfigSelectionArray {
                currentValue: Config.options.ai.tool
                onSelected: newValue => {
                    Config.options.ai.tool = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Functions"),
                        icon: "function",
                        value: "functions"
                    },
                    {
                        displayName: Translation.tr("Built-in search"),
                        icon: "travel_explore",
                        value: "search"
                    },
                    {
                        displayName: Translation.tr("None"),
                        icon: "close",
                        value: "none"
                    }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "search"
            text: Translation.tr("Web search and page fetching")
            checked: Config.options.ai.webSearch
            onCheckedChanged: {
                Config.options.ai.webSearch = checked;
            }
            StyledToolTip {
                text: Translation.tr("search_web and fetch_url, answered by the SearXNG on 127.0.0.1:8888")
            }
        }
        ConfigSwitch {
            buttonIcon: "smart_toy"
            text: Translation.tr("Hand a whole task to an agent")
            checked: Config.options.ai.agentTool
            onCheckedChanged: {
                Config.options.ai.agentTool = checked;
            }
            StyledToolTip {
                text: Translation.tr("ask_agent runs the pi CLI on this machine, unsandboxed")
            }
        }

        ContentSubsection {
            title: Translation.tr("Research mode")

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "repeat"
                    text: Translation.tr("Iterations")
                    value: Config.options.ai.research.maxIterations
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.ai.research.maxIterations = value;
                    }
                }
                ConfigSpinBox {
                    icon: "function"
                    text: Translation.tr("Tool calls each")
                    value: Config.options.ai.research.toolBudget
                    from: 1
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        Config.options.ai.research.toolBudget = value;
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "encrypted"
        title: Translation.tr("Approvals")

        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Let the agent tool run without asking")
            checked: Config.options.ai.approvals.agent
            onCheckedChanged: {
                Config.options.ai.approvals.agent = checked;
            }
            StyledToolTip {
                text: Translation.tr("ask_agent gets an unsandboxed shell, so this is one switch rather than a list")
            }
        }

        ContentSubsection {
            title: Translation.tr("Commands you said yes to for good")

            StyledText {
                Layout.fillWidth: true
                visible: Config.options.ai.approvals.shellRules.length === 0
                text: Translation.tr("Nothing yet. Choosing \"Always\" on a command approval adds it here.")
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            Repeater {
                model: Config.options.ai.approvals.shellRules
                delegate: RowLayout {
                    id: ruleRow
                    required property string modelData
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: ruleRow.modelData
                        font.family: Appearance.font.family.monospace
                        elide: Text.ElideRight
                    }
                    RippleButtonWithIcon {
                        materialIcon: "delete"
                        mainText: Translation.tr("Revoke")
                        onClicked: {
                            Config.options.ai.approvals.shellRules =
                                Config.options.ai.approvals.shellRules.filter(rule => rule !== ruleRow.modelData);
                        }
                    }
                }
            }

            RippleButtonWithIcon {
                visible: Config.options.ai.approvals.shellRules.length > 0
                materialIcon: "delete_sweep"
                mainText: Translation.tr("Revoke all")
                onClicked: {
                    Config.options.ai.approvals.shellRules = [];
                }
            }
        }
    }

    ContentSection {
        icon: "database"
        title: Translation.tr("Memory")

        ConfigSwitch {
            buttonIcon: "database"
            text: Translation.tr("Remember things between sessions")
            checked: Config.options.ai.memory.enable
            onCheckedChanged: {
                Config.options.ai.memory.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Needs koompi-agent-memd in ~/.local/bin.\nThe installer builds it; without it the assistant forgets everything at logout.")
            }
        }
        ConfigSwitch {
            enabled: Config.options.ai.memory.enable
            buttonIcon: "search_insights"
            text: Translation.tr("Look things up before every reply")
            checked: Config.options.ai.memory.autoRecall
            onCheckedChanged: {
                Config.options.ai.memory.autoRecall = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Recall")
            tooltip: Translation.tr("Past the budget the turn is sent without the recall rather than made to wait for it.")

            ConfigRow {
                uniform: true
                enabled: Config.options.ai.memory.enable
                ConfigSpinBox {
                    icon: "format_list_numbered"
                    text: Translation.tr("Memories recalled")
                    value: Config.options.ai.memory.recallCount
                    from: 0
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.ai.memory.recallCount = value;
                    }
                }
                ConfigSpinBox {
                    icon: "hourglass_top"
                    text: Translation.tr("Wait for them (ms)")
                    value: Config.options.ai.memory.recallBudgetMs
                    from: 1
                    to: 5000
                    stepSize: 100
                    onValueChanged: {
                        Config.options.ai.memory.recallBudgetMs = value;
                    }
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Embeddings")
            tooltip: Translation.tr("Local keeps every memory on this machine. The other two send the text to be embedded away.")

            ConfigSelectionArray {
                currentValue: Config.options.ai.memory.provider
                onSelected: newValue => {
                    Config.options.ai.memory.provider = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("On this machine"),
                        icon: "sync_saved_locally",
                        value: "local"
                    },
                    {
                        displayName: Translation.tr("Gemini"),
                        value: "gemini"
                    },
                    {
                        displayName: Translation.tr("OpenAI"),
                        value: "openai"
                    }
                ]
            }
            MaterialTextArea {
                Layout.fillWidth: true
                visible: Config.options.ai.memory.provider !== "local"
                placeholderText: Translation.tr("Keyring id for the embedding key")
                text: Config.options.ai.memory.keyId
                onTextChanged: Config.options.ai.memory.keyId = text
            }
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Daemon path (blank for ~/.local/bin/koompi-agent-memd)")
                text: Config.options.ai.memory.binary
                onTextChanged: Config.options.ai.memory.binary = text
            }
        }

        ContentSubsection {
            title: Translation.tr("Context and summarising")
            tooltip: Translation.tr("The window is read from the server where it says so, and these are the fallback and the fraction of it a conversation may fill before it is summarised.")

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "width_wide"
                    text: Translation.tr("Context window")
                    value: Config.options.ai.memory.contextWindow
                    from: 0
                    to: 1000000
                    stepSize: 1024
                    onValueChanged: {
                        Config.options.ai.memory.contextWindow = value;
                    }
                }
                ConfigSpinBox {
                    icon: "compress"
                    text: Translation.tr("Summarise past")
                    value: Config.options.ai.memory.compactionThreshold
                    from: 0
                    to: 1000000
                    stepSize: 1000
                    onValueChanged: {
                        Config.options.ai.memory.compactionThreshold = value;
                    }
                }
            }
            ConfigSlider {
                buttonIcon: "percent"
                text: Translation.tr("Fraction of the window")
                value: Config.options.ai.memory.compactionFraction
                from: 0.1
                to: 0.95
                onValueChanged: {
                    Config.options.ai.memory.compactionFraction = value;
                }
            }
            ConfigSpinBox {
                icon: "lan"
                text: Translation.tr("LiteRT-LM port")
                value: Config.options.ai.memory.litertPort
                from: 1
                to: 65535
                stepSize: 1
                onValueChanged: {
                    Config.options.ai.memory.litertPort = value;
                }
            }
        }
    }

    ContentSection {
        icon: "article"
        title: Translation.tr("System prompt")

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: Config.systemPromptOverridden ? "warning" : "check_circle"
            text: Config.systemPromptOverridden
                ? Translation.tr("The prompt below is the one in your own config file. It overrides the sections KOOMPI ships, and it will keep overriding them after an update.\n\nLive: %1").arg(Config.systemPromptSource)
                : Translation.tr("The prompt below is the one KOOMPI ships, composed from one file per section.\n\nLive: %1").arg(Config.systemPromptSource)
        }

        RippleButtonWithIcon {
            visible: Config.systemPromptOverridden
            materialIcon: "restore"
            mainText: Translation.tr("Use the shipped prompt instead")
            onClicked: {
                Config.options.ai.systemPrompt = Config.composedSystemPrompt;
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("System prompt")
            text: Config.options.ai.systemPrompt
            font.family: Appearance.font.family.monospace
            onTextChanged: {
                Qt.callLater(() => {
                    Config.options.ai.systemPrompt = text;
                });
            }
        }
    }

    ContentSection {
        icon: "chat"
        title: Translation.tr("Sidebar")

        ConfigSwitch {
            buttonIcon: "history"
            text: Translation.tr("Reopen the last conversation at login")
            checked: Config.options.ai.restoreSession
            onCheckedChanged: {
                Config.options.ai.restoreSession = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "animation"
            text: Translation.tr("Fade replies in as they arrive")
            checked: Config.options.sidebar.ai.textFadeIn
            onCheckedChanged: {
                Config.options.sidebar.ai.textFadeIn = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "bug_report"
            text: Translation.tr("Offer the developer commands")
            checked: Config.options.ai.debugCommands
            onCheckedChanged: {
                Config.options.ai.debugCommands = checked;
            }
        }
    }
}
