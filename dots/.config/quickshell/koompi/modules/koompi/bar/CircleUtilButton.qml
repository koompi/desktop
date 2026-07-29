import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

RippleButton {
    id: button

    required default property Item content
    property bool extraActiveCondition: false
    property string tooltipText: ""

    implicitHeight: Math.max(content.implicitHeight, 26, content.implicitHeight)
    implicitWidth: implicitHeight
    contentItem: content

    // PopupToolTip (own PopupWindow surface) so it renders below the bar,
    // not clipped inside the bar window like a QtQuick.Controls ToolTip.
    readonly property PopupToolTip toolTip: PopupToolTip {
        parent: button
        text: button.tooltipText
        extraVisibleCondition: button.tooltipText !== ""
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
    }
}
