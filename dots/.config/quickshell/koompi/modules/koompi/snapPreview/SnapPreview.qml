import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Shows where a dragged window will land before it is dropped, and drops it there.
 *
 * Hangs off the drag bind that already exists (`Super` + left drag) rather than
 * taking a pointer path of its own: `keybinds.lua` gives that chord a second,
 * transparent bind carrying the `snapPreviewDrag` global shortcut, so this sees
 * the press and the release of a drag Hyprland is running as usual.
 */
Scope {
    id: root

    // How close to an edge the pointer has to get before the drop snaps there.
    // Small on purpose: dragging a tiled window across the screen to swap it
    // with the one at the far edge is existing behaviour, and only a deliberate
    // push into the edge should become a snap instead.
    readonly property int edgeThreshold: 24
    readonly property real gap: Appearance.sizes.hyprlandGapsOut

    property bool dragging: false
    property real cursorX: -1
    property real cursorY: -1
    // Taken from the toplevel protocol rather than `hyprctl activewindow`, which
    // is re-parsed on a debounce and can lag the window that actually has focus.
    property string dragAddress: ""
    // The bind fires wherever the pointer is, so `Super`+drag on the desktop
    // background reaches here too, with the last focused window still active.
    // Acting on that would fling a window the user never touched, so the first
    // cursor reading of a drag has to land inside the window being dragged.
    property bool dragChecked: false
    property bool dragValid: false

    function screenAt(x, y) {
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i];
            if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height)
                return s;
        }
        return null;
    }

    // The first reading of a drag, against the window's pre-drag geometry: the
    // compositor emits no event while a window is dragged, so the client list
    // still holds where the window was when the button went down.
    function pointInWindow(x, y, win) {
        if (!win || !win.at || !win.size)
            return false;
        return x >= win.at[0] && x < win.at[0] + win.size[0] && y >= win.at[1] && y < win.at[1] + win.size[1];
    }

    /**
     * The whole of the zone maths, in one function so `tests/test_snap_zones.sh`
     * can lift it out and run it against fixtures. Screen-local coordinates in,
     * a screen-local rect out, null when the pointer is in no zone at all.
     *
     * `reserved` is Hyprland's [left, top, right, bottom] for the output, which
     * is what the bar takes.
     */
    function dropRectFor(width, height, reserved, localX, localY) {
        const nearLeft = localX <= root.edgeThreshold;
        const nearRight = localX >= width - 1 - root.edgeThreshold;
        const nearTop = localY <= root.edgeThreshold;
        const nearBottom = localY >= height - 1 - root.edgeThreshold;

        // A side takes a half and a corner a quarter. The top edge on its own
        // takes the lot; the bottom edge on its own takes nothing, because that
        // is where the dock lives.
        const side = nearLeft !== nearRight;
        if (!side && !(nearTop && !nearBottom))
            return null;
        const corner = side && (nearTop !== nearBottom);

        // The area a tiled window would get: the output minus what the bar
        // reserves, inset by the same gap Hyprland leaves around a tile.
        const usableX = reserved[0] + root.gap;
        const usableY = reserved[1] + root.gap;
        const usableW = width - reserved[0] - reserved[2] - root.gap * 2;
        const usableH = height - reserved[1] - reserved[3] - root.gap * 2;

        const w = side ? (usableW - root.gap) / 2 : usableW;
        const h = corner ? (usableH - root.gap) / 2 : usableH;
        return {
            x: usableX + (nearRight ? usableW - w : 0),
            y: usableY + ((corner && nearBottom) ? usableH - h : 0),
            width: w,
            height: h
        };
    }

    readonly property var dropScreen: (root.dragging && root.dragValid) ? root.screenAt(root.cursorX, root.cursorY) : null
    readonly property var dropMonitor: root.dropScreen
        ? (HyprlandData.monitors.find(m => m.name === root.dropScreen.name) ?? null)
        : null
    readonly property var dropRect: root.dropScreen
        ? root.dropRectFor(root.dropScreen.width, root.dropScreen.height, root.dropMonitor?.reserved ?? [0, 0, 0, 0], root.cursorX - root.dropScreen.x, root.cursorY - root.dropScreen.y)
        : null

    function begin() {
        root.dragAddress = ToplevelManager.activeToplevel?.HyprlandToplevel?.address ?? "";
        // Off every screen, so the last drag's zone cannot flash up before the
        // first cursor reading of this one arrives.
        root.cursorX = -1;
        root.cursorY = -1;
        root.dragChecked = false;
        root.dragValid = false;
        root.dragging = true;
    }

    function end() {
        const target = root.dropRect;
        const screen = root.dropScreen;
        root.dragging = false;
        if (!target || root.dragAddress.length === 0)
            return;
        const window = `window = "address:0x${root.dragAddress}"`;
        // Float first, because an exact geometry means nothing to a tiled window.
        // Then resize before moving: a resize keeps the window centred where it
        // is, so doing it second would undo the position.
        Hyprland.dispatch(`hl.dsp.window.float({ action = "on", ${window} })`);
        Hyprland.dispatch(`hl.dsp.window.resize({ x = ${Math.round(target.width)}, y = ${Math.round(target.height)}, ${window} })`);
        Hyprland.dispatch(`hl.dsp.window.move({ x = ${Math.round(screen.x + target.x)}, y = ${Math.round(screen.y + target.y)}, ${window} })`);
    }

    GlobalShortcut {
        name: "snapPreviewDrag"
        description: "Held for the length of a Super+drag, to preview where the window will land"

        onPressed: root.begin()
        onReleased: root.end()
    }

    // ponytail: polled, because Hyprland emits no cursor-motion event and its Lua
    // API has no way to hand the shell a payload. Runs only while a drag is live.
    // Swap it for an event the moment one exists.
    Timer {
        running: root.dragging
        interval: 60
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!cursorProcess.running)
            cursorProcess.running = true
    }

    Process {
        id: cursorProcess
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            id: cursorCollector
            onStreamFinished: {
                const parts = cursorCollector.text.trim().split(",");
                if (parts.length !== 2)
                    return;
                root.cursorX = parseInt(parts[0]);
                root.cursorY = parseInt(parts[1]);
                if (root.dragging && !root.dragChecked) {
                    root.dragChecked = true;
                    root.dragValid = root.pointInWindow(root.cursorX, root.cursorY, HyprlandData.windowByAddress[`0x${root.dragAddress}`]);
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: previewWindow
            required property var modelData
            screen: modelData

            visible: root.dropRect !== null && root.dropScreen === modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            // Above windows so it shows over the one being dragged, below the
            // overlay layer so it never covers the bar or a popup.
            WlrLayershell.namespace: "quickshell:snapPreview"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Empty: the drag owns the pointer and nothing here is clickable.
            mask: Region {}

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Rectangle {
                x: root.dropRect?.x ?? 0
                y: root.dropRect?.y ?? 0
                width: root.dropRect?.width ?? 0
                height: root.dropRect?.height ?? 0

                radius: Appearance.rounding.windowRounding
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                border.width: 2
                border.color: Appearance.colors.colPrimary

                Behavior on x {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
