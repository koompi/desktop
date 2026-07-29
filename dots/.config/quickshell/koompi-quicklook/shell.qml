// KOOMPI Quick Look - the preview surface behind `koompi-quicklook`.
//
// One layer-shell overlay that renders every previewable kind (image, video,
// audio, text, fallback) in the same card, so a preview always looks and
// behaves the same no matter what was selected. The launcher decides WHAT to
// show (mime -> kind) and passes it in through the environment; this file only
// decides how it looks.
//
// Env in: KOOMPI_QUICKLOOK_FILE, _KIND, _MIME, _NAME, _META, _WAVE, _SCREEN,
//         _PAGEDIR, _PAGECOUNT

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    readonly property string filePath: Quickshell.env("KOOMPI_QUICKLOOK_FILE") ?? ""
    readonly property string kind: Quickshell.env("KOOMPI_QUICKLOOK_KIND") ?? "other"
    readonly property string mime: Quickshell.env("KOOMPI_QUICKLOOK_MIME") ?? ""
    readonly property string fileName: Quickshell.env("KOOMPI_QUICKLOOK_NAME") ?? ""
    readonly property string meta: Quickshell.env("KOOMPI_QUICKLOOK_META") ?? ""
    readonly property string wavePath: Quickshell.env("KOOMPI_QUICKLOOK_WAVE") ?? ""
    readonly property string screenName: Quickshell.env("KOOMPI_QUICKLOOK_SCREEN") ?? ""
    readonly property string pageDir: Quickshell.env("KOOMPI_QUICKLOOK_PAGEDIR") ?? ""
    readonly property int pageCount: parseInt(Quickshell.env("KOOMPI_QUICKLOOK_PAGECOUNT") ?? "0") || 0
    // Material roles straight from the desktop palette matugen regenerates on
    // every wallpaper/mode change. No second theming pipeline, no fallback
    // hex soup beyond what is needed to still render if the file is missing.
    property var palette: ({})
    readonly property color cSurface: palette.surface_container ?? "#221f20"
    readonly property color cSurfaceHigh: palette.surface_container_high ?? "#2c292a"
    readonly property color cOnSurface: palette.on_surface ?? "#e8e1e1"
    readonly property color cOnSurfaceVar: palette.on_surface_variant ?? "#ccc5c6"
    readonly property color cPrimary: palette.primary ?? "#dac0c9"
    readonly property color cOutline: palette.outline_variant ?? "#4a4647"
    readonly property color cScrim: palette.scrim ?? "#000000"

    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/quickshell/user/generated/colors.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                shell.palette = JSON.parse(text());
            } catch (e) {}
        }
        Component.onCompleted: reload()
    }

    // Big files would freeze the preview; the header still reports the real
    // size so a truncated view is never mistaken for the whole file.
    property string textContent: ""

    FileView {
        path: shell.kind === "text" ? shell.filePath : ""
        onLoaded: shell.textContent = text().slice(0, 400000)
    }

    PanelWindow {
        id: win
        // The launcher resolves the focused monitor; preview must open where
        // the user is looking, not on whatever screen Qt enumerates first.
        // Falling back to the first screen matters: with no match the window
        // gets no output and the preview silently never appears.
        screen: Quickshell.screens.find(s => s.name === shell.screenName)
            ?? Quickshell.screens[0] ?? null
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        // "quickshell:" prefix on purpose: the shipped Hyprland layer rules
        // blur and un-dim every quickshell:* surface, so the preview picks up
        // the desktop's own material look without a new rule.
        WlrLayershell.namespace: "quickshell:quicklook"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // Card geometry. The preview occupies the same box a chat widget gets
        // (see the Telegram/Discord scratchpad rules): full monitor minus the
        // bar reserve, the 30px workspace gap and a 1px border. Media keeps its
        // own aspect inside that box so a portrait clip is not letterboxed into
        // a 16:9 slab; audio deliberately stays small - a waveform gains
        // nothing from being a metre wide.
        readonly property real barInset: 40
        readonly property real gap: 31
        readonly property real maxW: width - gap * 2
        readonly property real maxH: height - barInset - gap * 2
        property real contentAspect: 16 / 9
        readonly property real headerH: 46
        readonly property real bodyW: {
            if (shell.kind === "audio") return Math.min(maxW, 760);
            if (shell.kind === "other") return Math.min(maxW, 560);
            if (shell.kind === "text") return maxW;
            return Math.min(maxW, (maxH - headerH) * contentAspect);
        }
        readonly property real bodyH: {
            if (shell.kind === "audio") return 210;
            if (shell.kind === "other") return 230;
            if (shell.kind === "text") return maxH - headerH;
            // A document is read top to bottom, so it always takes the full
            // height available and lets the width follow the page aspect.
            if (shell.kind === "pages") return maxH - headerH;
            return Math.min(maxH - headerH, bodyW / contentAspect);
        }

        // Click-outside dismisses, but only once the surface has settled: a
        // click still in flight when the preview maps would close it instantly.
        property bool armed: false
        Timer { interval: 250; running: true; onTriggered: win.armed = true }

        // Driving the animation off a bound state rather than
        // Component.onCompleted matters: onCompleted runs before the surface is
        // mapped, so the open animation used to play against a window nobody
        // could see yet and the preview appeared already settled. One frame of
        // delay lets the first paint land, then the card animates for real.
        property bool shown: false
        property bool closing: false
        Timer { interval: 16; running: true; onTriggered: win.shown = true }

        // Every exit routes through here so the card animates out instead of
        // the window vanishing mid-frame. Qt.quit() is deferred by exactly the
        // out duration.
        function dismiss() {
            if (win.closing) return;
            win.closing = true;
            win.shown = false;
            quitTimer.start();
        }

        Timer { id: quitTimer; interval: 170; onTriggered: Qt.quit() }

        Rectangle {
            anchors.fill: parent
            color: shell.cScrim
            opacity: win.shown ? 0.42 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: win.closing ? 150 : 220
                    easing.type: Easing.OutCubic
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: if (win.armed) win.dismiss()
            }
        }

        // Whichever scrolling view is loaded registers itself here so the
        // arrow keys work without reaching for the mouse.
        property Flickable scroller: null

        function scroll(delta) {
            if (!scroller) return;
            const max = Math.max(0, scroller.contentHeight - scroller.height);
            scroller.contentY = Math.max(0, Math.min(max, scroller.contentY + delta));
        }

        Item {
            id: keyScope
            anchors.fill: parent
            focus: true
            // Space toggles the preview shut, the way Quick Look does. Media
            // playback is on Return/K instead so Space never has two meanings.
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Space:
                case Qt.Key_Escape:
                case Qt.Key_Q:
                    win.dismiss();
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_K:
                    if (player.hasMedia) player.toggle();
                    event.accepted = true;
                    break;
                case Qt.Key_Left:
                    if (player.hasMedia) player.position = Math.max(0, player.position - 5000);
                    else win.scroll(-win.height * 0.9);
                    event.accepted = true;
                    break;
                case Qt.Key_Right:
                    if (player.hasMedia) player.position = Math.min(player.duration, player.position + 5000);
                    else win.scroll(win.height * 0.9);
                    event.accepted = true;
                    break;
                case Qt.Key_Down:
                    win.scroll(120);
                    event.accepted = true;
                    break;
                case Qt.Key_Up:
                    win.scroll(-120);
                    event.accepted = true;
                    break;
                case Qt.Key_PageDown:
                    win.scroll(win.height * 0.9);
                    event.accepted = true;
                    break;
                case Qt.Key_PageUp:
                    win.scroll(-win.height * 0.9);
                    event.accepted = true;
                    break;
                case Qt.Key_Home:
                    win.scroll(-1e9);
                    event.accepted = true;
                    break;
                case Qt.Key_End:
                    win.scroll(1e9);
                    event.accepted = true;
                    break;
                }
            }
        }

        Rectangle {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            // Centred in the area below the bar, not the whole output, so the
            // card sits where a tiled window would.
            y: win.barInset + (win.height - win.barInset - height) / 2 + (win.shown ? 0 : 10)
            width: win.bodyW
            height: header.height + win.bodyH
            radius: 18
            color: Qt.rgba(shell.cSurface.r, shell.cSurface.g, shell.cSurface.b, 0.88)
            // No outline where the content reaches the edge: the border would
            // read as a stray white line along the media, not as a frame.
            border.width: ["image", "video", "pages"].indexOf(shell.kind) >= 0 ? 0 : 1
            border.color: Qt.rgba(shell.cOutline.r, shell.cOutline.g, shell.cOutline.b, 0.7)
            clip: true

            // Rises the last few pixels as it settles, which reads as the card
            // coming forward rather than simply fading up. The overshoot curve
            // is what gives it weight; a plain ease at this duration looks
            // slack.
            transformOrigin: Item.Center
            scale: win.shown ? 1 : 0.955
            opacity: win.shown ? 1 : 0
            Behavior on scale {
                NumberAnimation {
                    duration: win.closing ? 160 : 320
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: win.closing
                        ? [0.3, 0, 0.8, 0.15, 1, 1]
                        : [0.38, 1.21, 0.22, 1.00, 1, 1]
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: win.closing ? 140 : 200
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: win.closing ? 160 : 320
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.38, 1.21, 0.22, 1.00, 1, 1]
                }
            }

            // ---- Header ----
            Item {
                id: header
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: win.headerH

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 11
                    spacing: 12

                    Text {
                        // Never long enough to run under the centred app name.
                        Layout.maximumWidth: header.width * 0.30
                        text: shell.fileName
                        elide: Text.ElideMiddle
                        color: shell.cOnSurface
                        font { family: "Google Sans Flex"; pixelSize: 14; weight: Font.Medium }
                    }

                    // Size, page/line count, duration - reads as a subtitle of
                    // the file name, so it sits with it rather than opposite.
                    Text {
                        text: shell.meta
                        color: shell.cOnSurfaceVar
                        font { family: "Google Sans Flex"; pixelSize: 11 }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        radius: 13
                        color: closeArea.containsMouse
                            ? Qt.rgba(shell.cOnSurface.r, shell.cOnSurface.g, shell.cOnSurface.b, 0.12)
                            : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "close"
                            color: shell.cOnSurfaceVar
                            font { family: "Material Symbols Rounded"; pixelSize: 16 }
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: win.dismiss()
                        }
                    }
                }

                // Centred over the row, not inside it: the app name should stay
                // put no matter how long the file name is.
                Text {
                    anchors.centerIn: parent
                    // Hidden on the narrow cards, where it would collide with
                    // the file name rather than sit between name and close.
                    visible: header.width > 660
                    text: "KOOMPI Quicklook"
                    color: shell.cOnSurfaceVar
                    font { family: "Google Sans Flex"; pixelSize: 12; weight: Font.Medium }
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Qt.rgba(shell.cOutline.r, shell.cOutline.g, shell.cOutline.b, 0.6)
                }
            }

            // ---- Body ----
            Loader {
                anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                sourceComponent: {
                    switch (shell.kind) {
                    case "image": return imageView;
                    case "pages": return pagesView;
                    case "video": return videoView;
                    case "audio": return audioView;
                    case "text": return textView;
                    default: return otherView;
                    }
                }
            }
        }

        // Shared player for video and audio: same transport, same shortcuts,
        // one code path for both kinds.
        MediaPlayer {
            id: player
            readonly property bool hasMedia: shell.kind === "video" || shell.kind === "audio"
            source: hasMedia ? `file://${shell.filePath}` : ""
            audioOutput: AudioOutput {}
            videoOutput: null
            function toggle() { playbackState === MediaPlayer.PlayingState ? pause() : play(); }
            function fmt(ms) {
                if (!(ms > 0)) ms = 0;
                const t = Math.floor(ms / 1000);
                const m = Math.floor(t / 60), s = t % 60;
                return `${m}:${s < 10 ? "0" : ""}${s}`;
            }
            onMediaStatusChanged: {
                if (mediaStatus === MediaPlayer.LoadedMedia) {
                    if (shell.kind === "video" && metaData.value(MediaMetaData.Resolution)) {
                        const r = metaData.value(MediaMetaData.Resolution);
                        if (r.width > 0 && r.height > 0) win.contentAspect = r.width / r.height;
                    }
                    play();
                }
            }
        }

        // ---- Kind components ----

        Component {
            id: imageView
            Item {
                Image {
                    id: img
                    anchors.fill: parent
                    source: `file://${shell.filePath}`
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    // Downscale huge photos in the decoder, not the GPU.
                    sourceSize.width: Math.round(win.maxW)
                    onStatusChanged: {
                        if (status === Image.Ready && implicitHeight > 0)
                            win.contentAspect = implicitWidth / implicitHeight;
                    }
                }
            }
        }

        // PDFs arrive as a directory of page-N.png that the launcher renders
        // page 1 first and streams the rest into while this is already on
        // screen, so a page that is not on disk yet is expected rather than an
        // error: each one retries until its file lands.
        Component {
            id: pagesView
            Item {
                ListView {
                    id: pageList
                    anchors.fill: parent
                    anchors.topMargin: 12
                    anchors.bottomMargin: 12
                    spacing: 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: shell.pageCount
                    cacheBuffer: 4000
                    Component.onCompleted: win.scroller = this

                    delegate: Item {
                        id: pageItem
                        required property int index
                        width: pageList.width
                        height: pageImage.height

                        Image {
                            id: pageImage
                            readonly property string pagePath: `file://${shell.pageDir}/page-${pageItem.index + 1}.png`
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(pageList.width - 24, 1100)
                            // Height comes from the page's own aspect rather
                            // than from paintedHeight, which would depend on
                            // the delegate height this feeds and loop.
                            // Before the file lands there is no aspect to go
                            // on, so a full-height placeholder holds the scroll
                            // position steady while later pages stream in.
                            height: implicitWidth > 0 && implicitHeight > 0
                                ? width * (implicitHeight / implicitWidth)
                                : pageList.height
                            source: pagePath
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            sourceSize.width: 1100
                            onStatusChanged: {
                                if (status === Image.Error)
                                    retry.start();
                                // The first page decides how wide the card is,
                                // so a portrait document is not framed in a
                                // landscape slab.
                                else if (status === Image.Ready && pageItem.index === 0 && implicitHeight > 0)
                                    win.contentAspect = implicitWidth / implicitHeight;
                            }

                            // Clearing the source first is required: Qt caches
                            // the failure, so re-assigning the same path alone
                            // would never re-read the file once it appears.
                            Timer {
                                id: retry
                                interval: 350
                                repeat: false
                                onTriggered: {
                                    pageImage.source = "";
                                    pageImage.source = pageImage.pagePath;
                                }
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: videoView
            Item {
                VideoOutput {
                    id: vo
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                    Component.onCompleted: player.videoOutput = vo
                }
                MouseArea { anchors.fill: parent; onClicked: player.toggle() }
                Transport { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } overlay: true }
            }
        }

        Component {
            id: audioView
            Item {
                // Waveform runs edge to edge like a page or a photo; the
                // transport is the only chrome, pinned to the bottom.
                Image {
                    anchors { left: parent.left; right: parent.right
                              top: parent.top; bottom: transport.top }
                    source: shell.wavePath ? `file://${shell.wavePath}` : ""
                    fillMode: Image.Stretch
                    visible: status === Image.Ready
                    smooth: true
                }

                Text {
                    anchors.centerIn: parent
                    visible: !shell.wavePath
                    text: "graphic_eq"
                    color: shell.cPrimary
                    font { family: "Material Symbols Rounded"; pixelSize: 56 }
                }

                Rectangle {
                    anchors { top: parent.top; bottom: transport.top }
                    width: 2
                    x: player.duration > 0
                        ? parent.width * (player.position / player.duration) : 0
                    visible: player.duration > 0
                    color: shell.cOnSurface
                }

                Transport {
                    id: transport
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                }
            }
        }

        Component {
            id: textView
            Item {
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 16
                    contentWidth: width
                    contentHeight: textBody.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                Component.onCompleted: win.scroller = this

                    Text {
                        id: textBody
                        width: parent.width
                        text: shell.textContent
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        color: shell.cOnSurface
                        font { family: "JetBrains Mono NF"; pixelSize: 12 }
                        textFormat: Text.PlainText
                    }
                }
            }
        }

        Component {
            id: otherView
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "draft"
                    color: shell.cPrimary
                    font { family: "Material Symbols Rounded"; pixelSize: 40 }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: shell.mime
                    color: shell.cOnSurfaceVar
                    font { family: "Google Sans Flex"; pixelSize: 12 }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("No preview available")
                    color: shell.cOnSurface
                    font { family: "Google Sans Flex"; pixelSize: 13 }
                }

                // Nothing local can render this, but Drive can. Offering the
                // handoff beats a dead end.
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 10
                    implicitWidth: driveRow.implicitWidth + 28
                    implicitHeight: 34
                    radius: 17
                    color: driveArea.containsMouse ? shell.cPrimary
                        : Qt.rgba(shell.cPrimary.r, shell.cPrimary.g, shell.cPrimary.b, 0.16)

                    RowLayout {
                        id: driveRow
                        anchors.centerIn: parent
                        spacing: 7
                        Text {
                            text: "cloud_upload"
                            color: driveArea.containsMouse ? shell.cSurface : shell.cPrimary
                            font { family: "Material Symbols Rounded"; pixelSize: 17 }
                        }
                        Text {
                            text: qsTr("Open in Google Drive")
                            color: driveArea.containsMouse ? shell.cSurface : shell.cPrimary
                            font { family: "Google Sans Flex"; pixelSize: 12; weight: Font.Medium }
                        }
                    }

                    MouseArea {
                        id: driveArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            driveProc.running = true;
                            win.dismiss();
                        }
                    }
                }

                Process {
                    id: driveProc
                    // Detached: the preview quits immediately after clicking,
                    // and a child of a dead Process would go with it.
                    command: ["setsid", "-f", "koompi-quicklook", "drive", shell.filePath]
                }
            }
        }

        component Transport: Item {
            property bool overlay: false
            implicitHeight: 44

            Rectangle {
                anchors.fill: parent
                visible: parent.overlay
                gradient: Gradient {
                    GradientStop { position: 0; color: "#00000000" }
                    GradientStop { position: 1; color: "#99000000" }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                Text {
                    text: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play_arrow"
                    color: parent.parent.overlay ? "#ffffff" : shell.cOnSurface
                    font { family: "Material Symbols Rounded"; pixelSize: 24 }
                    MouseArea { anchors.fill: parent; onClicked: player.toggle() }
                }

                Text {
                    text: player.fmt(player.position)
                    color: parent.parent.overlay ? "#ffffff" : shell.cOnSurfaceVar
                    font { family: "JetBrains Mono NF"; pixelSize: 11 }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 16

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(shell.cOnSurface.r, shell.cOnSurface.g, shell.cOnSurface.b, 0.25)

                        Rectangle {
                            width: player.duration > 0
                                ? parent.width * (player.position / player.duration)
                                : 0
                            height: parent.height
                            radius: 2
                            color: shell.cPrimary
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: mouse => {
                            if (player.duration > 0)
                                player.position = player.duration * (mouse.x / width);
                        }
                    }
                }

                Text {
                    text: player.fmt(player.duration)
                    color: parent.parent.overlay ? "#ffffff" : shell.cOnSurfaceVar
                    font { family: "JetBrains Mono NF"; pixelSize: 11 }
                }
            }
        }
    }
}
