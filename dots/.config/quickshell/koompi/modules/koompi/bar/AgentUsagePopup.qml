pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    // Fixed display order for the providers we know about; anything else
    // AgentUsage.providers might carry in future (unlikely, but the JSON
    // format doesn't forbid it) still shows, just after these three.
    readonly property var providerOrder: ["claude", "codex", "pi"]
    readonly property var providerMeta: ({
        claude: {
            icon: "smart_toy",
            label: "Claude Code"
        },
        codex: {
            icon: "terminal",
            label: "Codex"
        },
        pi: {
            icon: "bolt",
            label: "Pi"
        }
    })
    readonly property string todayKey: new Date().toISOString().slice(0, 10)
    readonly property var sectionKeys: {
        const known = AgentUsage.providers ?? {};
        const rest = Object.keys(known).filter(key => !root.providerOrder.includes(key));
        return root.providerOrder.filter(key => key in known).concat(rest);
    }

    function formatTokens(n) {
        const value = n ?? 0;
        if (value >= 1000000)
            return (value / 1000000).toFixed(1) + "M";
        if (value >= 1000)
            return (value / 1000).toFixed(1) + "k";
        return String(value);
    }
    // Top few models by total tokens - a session can pick up several models
    // (retries, subagents on cheaper models, ...) and the popup only has room
    // for a handful before it stops being a glance.
    function topModels(provider) {
        const models = provider?.byModel ?? {};
        return Object.keys(models).map(name => ({
            name: name,
            tokens: models[name].totalTokens ?? 0
        })).sort((a, b) => b.tokens - a.tokens).slice(0, 3);
    }

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            model: root.sectionKeys
            delegate: ColumnLayout {
                id: section
                required property string modelData
                readonly property var provider: AgentUsage.providers[modelData]
                readonly property var meta: root.providerMeta[modelData] ?? {
                    icon: "smart_toy",
                    label: modelData
                }
                spacing: 4

                StyledPopupHeaderRow {
                    icon: section.meta.icon
                    label: section.meta.label
                }

                StyledPopupValueRow {
                    icon: "today"
                    label: Translation.tr("Today:")
                    value: root.formatTokens(section.provider?.byDay?.[root.todayKey]?.totalTokens)
                }

                StyledPopupValueRow {
                    icon: "empty_dashboard"
                    label: Translation.tr("Total:")
                    value: root.formatTokens(section.provider?.totalTokens)
                }

                Repeater {
                    model: root.topModels(section.provider)
                    delegate: StyledPopupValueRow {
                        required property var modelData
                        icon: "model_training"
                        label: modelData.name + ":"
                        value: root.formatTokens(modelData.tokens)
                    }
                }
            }
        }
    }
}
