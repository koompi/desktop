import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    icon: "voting_chip"
    title: Translation.tr("On-screen display")

    ConfigSpinBox {
        icon: "av_timer"
        text: Translation.tr("Timeout (ms)")
        value: Config.options.osd.timeout
        from: 100
        to: 3000
        stepSize: 100
        onValueChanged: {
            Config.options.osd.timeout = value;
        }
    }
}
