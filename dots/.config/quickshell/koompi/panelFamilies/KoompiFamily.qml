import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.koompi.background
import qs.modules.koompi.bar
import qs.modules.koompi.cheatsheet
import qs.modules.koompi.dock
import qs.modules.koompi.launchpad
import qs.modules.koompi.lock
import qs.modules.koompi.mediaControls
import qs.modules.koompi.notificationPopup
import qs.modules.koompi.onScreenDisplay
import qs.modules.koompi.onScreenKeyboard
import qs.modules.koompi.overview
import qs.modules.koompi.polkit
import qs.modules.koompi.regionSelector
import qs.modules.koompi.screenCorners
import qs.modules.koompi.screenTranslator
import qs.modules.koompi.sessionScreen
import qs.modules.koompi.sidebarLeft
import qs.modules.koompi.sidebarRight
import qs.modules.koompi.overlay
import qs.modules.koompi.verticalBar
import qs.modules.koompi.wallpaperSelector
import qs.modules.koompi.scratchpadDismiss

Scope {
    PanelLoader { extraCondition: !Config.options.bar.vertical; component: Bar {} }
    PanelLoader { component: Background {} }
    PanelLoader { component: Cheatsheet {} }
    PanelLoader { extraCondition: Config.options.dock.enable; component: Dock {} }
    PanelLoader { component: Launchpad {} }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader { component: NotificationPopup {} }
    PanelLoader { component: OnScreenDisplay {} }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: Overview {} }
    PanelLoader { component: Polkit {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader { component: ScreenCorners {} }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader { component: SidebarLeft {} }
    PanelLoader { component: SidebarRight {} }
    PanelLoader { extraCondition: Config.options.bar.vertical; component: VerticalBar {} }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader { component: ScratchpadDismiss {} }
}
