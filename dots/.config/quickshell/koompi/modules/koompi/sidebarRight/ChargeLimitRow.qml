import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Battery health behind one drawer click: the pack stops charging at the
// end-threshold and resumes below the start-threshold, which keeps it off a
// permanent 100% float. UPower owns the state; the switch answers instantly
// and then re-binds to whatever came back.
ConfigSwitch {
    Layout.fillWidth: true
    visible: ChargeLimit.supported
    iconSize: Appearance.font.pixelSize.larger
    buttonIcon: "battery_saver"
    text: Translation.tr("Limit charging to %1%").arg(ChargeLimit.endThreshold)
    checked: ChargeLimit.enabled

    onCheckedChanged: {
        ChargeLimit.setEnabled(checked);
        // ConfigSwitch assigns checked on click, killing the binding.
        // UPower owns this value, so it has to come back.
        checked = Qt.binding(() => ChargeLimit.enabled);
    }

    StyledToolTip {
        text: Translation.tr("Charging stops at %1% and resumes below %2%. Less range today, more capacity in a few years.").arg(ChargeLimit.endThreshold).arg(ChargeLimit.startThreshold)
    }
}
