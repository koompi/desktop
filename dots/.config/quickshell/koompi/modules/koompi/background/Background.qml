pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import qs.modules.common.models.hyprland
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.koompi.background.widgets
import qs.modules.koompi.background.widgets.clock
import qs.modules.koompi.background.widgets.weather

Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: bgRoot

        required property var modelData

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10
        property int workspaceChunkSize: Config?.options.bar.workspaces.shown ?? 10
        property int totalWorkspaces: Math.ceil(lastWorkspaceId / workspaceChunkSize) * workspaceChunkSize
        // Wallpaper
        property int activeWorkspaceId: bgRoot.monitor?.activeWorkspace?.id ?? 1
        readonly property bool wallpaperIsVideo: Wallpapers.isVideoPath(Wallpapers.rawForWorkspace(bgRoot.activeWorkspaceId))
        property string wallpaperPath: Wallpapers.forWorkspace(bgRoot.activeWorkspaceId)
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        readonly property real parallaxRation: Config.options.background.parallax.workspaceZoom
        property real minSuitableScale: 1 // Some reasonable init, to be updated
        property real effectiveWallpaperScale: minSuitableScale * parallaxRation
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        property real scaledWallpaperWidth: wallpaperWidth * effectiveWallpaperScale
        property real scaledWallpaperHeight: wallpaperHeight * effectiveWallpaperScale
        property real parallaxTotalPixelsX: Math.max(0, scaledWallpaperWidth - screen.width)
        property real parallaxTotalPixelsY: Math.max(0, scaledWallpaperHeight - screen.height)
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Colors
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        // Strictly the desktop background. The session lock draws its own
        // wallpaper on its own surface, which the compositor composites above
        // every layer-shell layer, so raising this one while locked only ever
        // produced a second wallpaper nobody could see.
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated

            // Same workspace, different picture: there is nowhere to travel
            // from, so just swap it. Guarded because this also fires as part of
            // a workspace change, where the pan is already handling it.
            if (!panAnimation.running && wallpaperPan.armedWorkspaceId === 0 && bgRoot.shownWorkspaceId === bgRoot.activeWorkspaceId)
                wallpaperPan.settle(bgRoot.wallpaperPath);
        }

        // Video wallpaper, work-safety blank and a bad path never produce a Ready image, so
        // the timer is the floor under the handoff curtain at the bottom of this file.
        property bool wallpaperArrived: false
        Timer {
            interval: 3000
            running: true
            onTriggered: bgRoot.wallpaperArrived = true
        }

        // Which workspace the wallpaper on screen belongs to. Hyprland slides
        // the windows of both workspaces across, so the wallpaper has to travel
        // with them; swapping the source in place is the blink.
        property int shownWorkspaceId: 1
        Component.onCompleted: {
            bgRoot.shownWorkspaceId = bgRoot.activeWorkspaceId;
            wallpaperPan.currentCell.path = Wallpapers.forWorkspace(bgRoot.activeWorkspaceId);
            // Neither of these ever produces a Ready image.
            if (bgRoot.wallpaperIsVideo || bgRoot.wallpaperSafetyTriggered)
                bgRoot.wallpaperArrived = true;
        }
        onActiveWorkspaceIdChanged: {
            // Ask the service rather than reading wallpaperPath: that binding
            // and this handler wake on the same change, in no guaranteed order.
            const id = bgRoot.activeWorkspaceId;
            const direction = id > bgRoot.shownWorkspaceId ? 1 : -1;
            bgRoot.shownWorkspaceId = id;

            // A swipe has already loaded this workspace into the far cell and
            // dragged it most of the way here. Let it finish its travel instead
            // of restarting it from the screen edge.
            if (wallpaperPan.armedWorkspaceId === id)
                wallpaperPan.commit();
            else
                wallpaperPan.switchTo(Wallpapers.forWorkspace(id), direction);
        }

        // Hyprland moves a workspace by the monitor width plus the gap between
        // workspaces; the wallpaper only has a monitor to move across, so swipe
        // offsets are scaled down by the difference.
        HyprlandConfigOption {
            id: workspaceGapOption
            key: "general:gaps_workspaces"
        }
        readonly property real swipeScale: bgRoot.screen.width / (bgRoot.screen.width + (workspaceGapOption.value ?? 0))

        Connections {
            target: Hyprland

            function onRawEvent(event): void {
                if (!event.name.startsWith("koompiswipe"))
                    return;

                if (event.name === "koompiswipeend") {
                    // A cancelled swipe never changes workspace, so nothing has
                    // called commit; put the wallpaper back where it started.
                    if (wallpaperPan.armedWorkspaceId !== 0)
                        wallpaperPan.cancel();
                    return;
                }
                if (event.name !== "koompiswipe")
                    return;

                const args = event.data.split(",");
                if (args[0] !== bgRoot.monitor?.name)
                    return;

                const targetId = parseInt(args[1]);
                const offset = parseFloat(args[2]) * bgRoot.swipeScale;
                wallpaperPan.arm(targetId, Wallpapers.forWorkspace(targetId), offset > 0 ? -1 : 1);
                wallpaperPan.track(offset);
            }
        }

        // Parallax, shared by both cells so the two wallpapers in a switch agree
        // on framing and the handover at the end of one is invisible.
        property real wallpaperFraction: {
            // 0 - start of the picture, 1 - end of the picture
            if (bgRoot.totalWorkspaces <= 1)
                return 0.5;
            return Math.max(0, Math.min(1, (bgRoot.activeWorkspaceId - 1) / (bgRoot.totalWorkspaces - 1)));
        }
        property real wallpaperFractionX: {
            let usedFraction = 0.5;
            if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax)
                usedFraction = bgRoot.wallpaperFraction;
            if (Config.options.background.parallax.enableSidebar) {
                let sidebarFraction = bgRoot.parallaxRation / bgRoot.workspaceChunkSize / 2;
                usedFraction += (sidebarFraction * GlobalStates.sidebarRightOpen - sidebarFraction * GlobalStates.sidebarLeftOpen);
            }
            return Math.max(0, Math.min(1, usedFraction));
        }
        property real wallpaperFractionY: {
            if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax)
                return bgRoot.wallpaperFraction;
            return 0.5;
        }
        property real wallpaperImageX: bgRoot.screen.width > bgRoot.scaledWallpaperWidth ? (bgRoot.screen.width - bgRoot.scaledWallpaperWidth) / 2 : -bgRoot.parallaxTotalPixelsX * bgRoot.wallpaperFractionX
        property real wallpaperImageY: bgRoot.screen.height > bgRoot.scaledWallpaperHeight ? (bgRoot.screen.height - bgRoot.scaledWallpaperHeight) / 2 : -bgRoot.parallaxTotalPixelsY * bgRoot.wallpaperFractionY
        Behavior on wallpaperImageX {
            NumberAnimation {
                duration: Appearance.animationDuration.slowest
                easing.type: Easing.OutCubic
            }
        }
        Behavior on wallpaperImageY {
            NumberAnimation {
                duration: Appearance.animationDuration.slowest
                easing.type: Easing.OutCubic
            }
        }

        // Wallpaper zoom scale
        function updateZoomScale() {
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            // [0]: first frame only. On an animated image identify prints one
            // "%w %h" per frame, back to back, and the second number comes out wrong.
            command: ["magick", "identify", "-format", "%w %h", `${path}[0]`]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text.trim();
                    const [width, height] = output.split(" ").map(Number);
                    if (!(Number.isFinite(width) && width > 0 && Number.isFinite(height) && height > 0)) {
                        // Nothing or garbage from identify: keep the previous size
                        // rather than feeding NaN/Infinity into every offset below.
                        console.warn(`[Background] Could not read the size of ${getWallpaperSizeProc.path}: identify printed "${output}"`);
                        return;
                    }
                    const [screenWidth, screenHeight] = [bgRoot.screen.width, bgRoot.screen.height];
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;

                    // Perfect image; scale = 1
                    // Small picture; scale > 1; will zoom in the picture
                    // Big picture; scale < 1; will zoom out the picture
                    // Choose max number so every side will fit
                    bgRoot.minSuitableScale = Math.max(screenWidth / width, screenHeight / height);
                }
            }
        }

        Item {
            anchors.fill: parent

            // Travel is one screen width, not width + gaps_workspaces: matching the windows
            // exactly opens a seam of bare layer between the two wallpapers.
            Item {
                id: wallpaperPan
                width: parent.width
                height: parent.height

                // The cells swap roles rather than swapping sources, so a swipe
                // that commits carries on from where the finger left it instead
                // of restarting from the screen edge.
                property Item currentCell: cellA
                readonly property Item otherCell: currentCell === cellA ? cellB : cellA
                // Workspace the far cell is loaded with, 0 when nothing is armed.
                property int armedWorkspaceId: 0

                function arm(workspaceId: int, path: string, direction: int): void {
                    if (wallpaperPan.armedWorkspaceId === workspaceId)
                        return;
                    wallpaperPan.armedWorkspaceId = workspaceId;
                    wallpaperPan.otherCell.path = path;
                    wallpaperPan.otherCell.x = wallpaperPan.currentCell.x + direction * wallpaperPan.width;
                }

                function track(offset: real): void {
                    panAnimation.stop();
                    wallpaperPan.x = -wallpaperPan.currentCell.x + offset;
                }

                function commit(): void {
                    wallpaperPan.armedWorkspaceId = 0;
                    wallpaperPan.currentCell = wallpaperPan.otherCell;
                    panAnimation.restart();
                }

                function cancel(): void {
                    wallpaperPan.armedWorkspaceId = 0;
                    panAnimation.restart();
                }

                function switchTo(path: string, direction: int): void {
                    wallpaperPan.otherCell.path = path;
                    wallpaperPan.otherCell.x = wallpaperPan.currentCell.x + direction * wallpaperPan.width;
                    wallpaperPan.commit();
                }

                // Blanked or handed over to a video: no travel to animate.
                function settle(path: string): void {
                    panAnimation.stop();
                    wallpaperPan.armedWorkspaceId = 0;
                    wallpaperPan.currentCell.path = path;
                    wallpaperPan.normalise();
                }

                // Bring the pan back to zero without moving anything on screen.
                // Both cells shift by the same amount: leaving the far one where
                // it was drops it straight back on top of the near one, which is
                // the blink this whole thing exists to avoid.
                function normalise(): void {
                    const shift = wallpaperPan.currentCell.x;
                    wallpaperPan.currentCell.x = 0;
                    wallpaperPan.otherCell.x -= shift;
                    wallpaperPan.x = 0;
                }

                NumberAnimation {
                    id: panAnimation
                    target: wallpaperPan
                    property: "x"
                    to: -wallpaperPan.currentCell.x
                    // Mirrors the workspaces animation in hyprland/general.lua.
                    // Hyprland animates whatever is left of the distance over
                    // this same fixed duration, so a half finished swipe lands
                    // with the windows rather than after them.
                    duration: Appearance.animationDuration.slow
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Appearance.animationCurves.workspaceSlide
                    // Re-zero once still, or cell offsets walk off after a few
                    // hundred switches. The far cell keeps its picture: it is
                    // off screen, and the workspace switched away from is the
                    // one most likely to be switched back to.
                    onFinished: wallpaperPan.normalise()
                }

                Item {
                    id: cellA
                    property alias path: cellAImage.source
                    width: wallpaperPan.width
                    height: wallpaperPan.height
                    clip: true

                    // Not StyledImage: its sourceSize follows the layout size. The magick zoom scale
                    // arrives a few frames into a switch and re-decodes at the corrected size, so
                    // opacity holds through a reload of the source already shown - dropping it there
                    // is the dark blink. retainWhileLoading keeps that frame up meanwhile.
                    Image {
                        id: cellAImage
                        property url readySource
                        onStatusChanged: if (status === Image.Ready) {
                            readySource = source;
                            bgRoot.wallpaperArrived = true;
                        }
                        x: bgRoot.wallpaperImageX
                        y: bgRoot.wallpaperImageY
                        width: bgRoot.scaledWallpaperWidth
                        height: bgRoot.scaledWallpaperHeight
                        sourceSize.width: Math.ceil(bgRoot.scaledWallpaperWidth)
                        sourceSize.height: Math.ceil(bgRoot.scaledWallpaperHeight)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        retainWhileLoading: true
                        visible: opacity > 0
                        opacity: ((status === Image.Ready || source === readySource) && !bgRoot.wallpaperIsVideo && !bgRoot.wallpaperSafetyTriggered) ? 1 : 0
                    }
                }

                Item {
                    id: cellB
                    property alias path: cellBImage.source
                    width: wallpaperPan.width
                    height: wallpaperPan.height
                    clip: true

                    // Not StyledImage, same reason as the outgoing cell above.
                    Image {
                        id: cellBImage
                        property url readySource
                        onStatusChanged: if (status === Image.Ready) {
                            readySource = source;
                            bgRoot.wallpaperArrived = true;
                        }
                        x: bgRoot.wallpaperImageX
                        y: bgRoot.wallpaperImageY
                        width: bgRoot.scaledWallpaperWidth
                        height: bgRoot.scaledWallpaperHeight
                        sourceSize.width: Math.ceil(bgRoot.scaledWallpaperWidth)
                        sourceSize.height: Math.ceil(bgRoot.scaledWallpaperHeight)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        retainWhileLoading: true
                        visible: opacity > 0
                        opacity: ((status === Image.Ready || source === readySource) && !bgRoot.wallpaperIsVideo && !bgRoot.wallpaperSafetyTriggered) ? 1 : 0
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                width: parent.width
                height: parent.height
                readonly property real parallaxFactor: {
                    var f = Config.options.background.parallax.widgetsFactor;
                    return f / bgRoot.parallaxRation;
                }
                readonly property real baseWallpaperOffsetX: (bgRoot.screen.width - bgRoot.scaledWallpaperWidth) / 2
                readonly property real baseWallpaperOffsetY: (bgRoot.screen.height - bgRoot.scaledWallpaperHeight) / 2
                readonly property real wallpaperTotalOffsetX: bgRoot.wallpaperImageX - baseWallpaperOffsetX
                readonly property real wallpaperTotalOffsetY: bgRoot.wallpaperImageY - baseWallpaperOffsetY
                x: wallpaperTotalOffsetX * parallaxFactor
                y: wallpaperTotalOffsetY * parallaxFactor

                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    }
                }
            }
        }

        // Keep in step with misc:background_color in hypr/hyprland/colors.lua and
        // transitionColor in the SDDM theme.conf; tests/test_login_handoff.sh holds the
        // three together.
        Rectangle {
            anchors.fill: parent
            color: "#121318"
            visible: opacity > 0
            opacity: bgRoot.wallpaperArrived ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animationDuration.slow
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
