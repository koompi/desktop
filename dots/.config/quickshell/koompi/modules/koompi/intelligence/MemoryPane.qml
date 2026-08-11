import qs.modules.common
import qs.modules.koompi.sidebarLeft.aiChat.memory
import QtQuick

// J05 built the browser to be embeddable and it is embedded, not reimplemented.
// The standalone window and the sidebar mount this same item.
FocusScope {
    id: root

    MemoryBrowser {
        anchors.fill: parent
        active: true
    }
}
