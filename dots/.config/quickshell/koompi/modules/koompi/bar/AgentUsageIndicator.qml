import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless

    readonly property var providers: AgentUsage.providers
    readonly property string todayKey: new Date().toISOString().slice(0, 10)

    // Sum of today's totalTokens across every provider present in the file -
    // the bar shows one number, the popup breaks it down per provider/model.
    function todayTokens() {
        let total = 0;
        for (const key in root.providers) {
            const day = root.providers[key]?.byDay?.[root.todayKey];
            total += day?.totalTokens ?? 0;
        }
        return total;
    }
    function formatTokens(n) {
        if (n >= 1000000)
            return (n / 1000000).toFixed(1) + "M";
        if (n >= 1000)
            return (n / 1000).toFixed(1) + "k";
        return String(n);
    }

    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    RowLayout {
        id: rowLayout
        spacing: 4
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "smart_toy"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.normal
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colOnLayer1
            text: root.formatTokens(root.todayTokens())
        }
    }

    AgentUsagePopup {
        hoverTarget: root
    }
}
