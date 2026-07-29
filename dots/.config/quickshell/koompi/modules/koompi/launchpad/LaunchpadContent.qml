pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import "paging.js" as Paging

FocusScope {
    id: root

    property bool active: false

    // The grid never runs under the bar, the same reserve Quick Look uses.
    readonly property real barInset: 40
    readonly property int columns: 7
    readonly property int rows: 5
    readonly property int pageSize: columns * rows

    property string query: ""
    property int selectedIndex: 0

    // What counts as an app someone actually opens, versus a tool that only
    // exists because something else installed it. Front is checked before
    // tools so an IDE stays an IDE and is not demoted for also being tagged
    // Development.
    readonly property var frontCategories: ["WebBrowser", "IDE", "TextEditor", "TerminalEmulator", "Office", "FileManager", "AudioVideo", "Audio", "Video", "Graphics", "Photography", "InstantMessaging", "Chat", "Email", "Player", "Game", "Spreadsheet", "WordProcessor", "Presentation"]
    readonly property var toolCategories: ["Settings", "System", "HardwareSettings", "Monitor", "Development", "Building", "Debugger", "Profiling", "RevisionControl", "Translation", "Documentation", "ConsoleOnly"]
    // AI apps rarely carry a category that says so - most ship Utility or
    // nothing - so they are named outright rather than guessed at.
    readonly property var frontNames: ["claude", "chatgpt", "lm studio", "lmstudio", "ollama", "openwork", "cursor", "windsurf", "jan", "msty", "obsidian", "zed"]

    function tier(entry) {
        const name = (entry.name ?? "").toLowerCase();
        if (root.frontNames.some(n => name.indexOf(n) !== -1))
            return 0;
        const cats = entry.categories ?? [];
        if (cats.some(c => root.frontCategories.indexOf(c) !== -1))
            return 0;
        if (cats.some(c => root.toolCategories.indexOf(c) !== -1))
            return 2;
        return 1;
    }

    // Anything actually launched leads, whatever it is - a tool you reach for
    // daily should not be buried on page two. Past that, user-facing apps come
    // before tools, and ties fall back to alphabetical so the grid is stable.
    readonly property var allApps: AppSearch.list
        .filter(a => !a.noDisplay)
        .slice()
        .sort((a, b) => {
            const scoreA = LaunchpadUsage.score(a.id);
            const scoreB = LaunchpadUsage.score(b.id);
            if (scoreA !== scoreB)
                return scoreB - scoreA;
            const tierA = root.tier(a);
            const tierB = root.tier(b);
            if (tierA !== tierB)
                return tierA - tierB;
            return a.name.localeCompare(b.name);
        })
    readonly property var apps: root.query.length === 0
        ? root.allApps
        : AppSearch.fuzzyQuery(root.query).filter(a => !a.noDisplay)
    readonly property int pageCount: Math.max(1, Math.ceil(root.apps.length / root.pageSize))

    function reset() {
        root.query = "";
        root.selectedIndex = 0;
        root.launchingId = "";
        launchCloseTimer.stop();
        pager.goTo(0, false);
        searchInput.text = "";
        // Claiming focus here alone is not enough: reset() runs the moment the
        // state flips, before the layer surface is mapped, so the grab lands on
        // a window that does not exist yet and typing goes nowhere.
        focusTimer.restart();
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: searchInput.forceActiveFocus()
    }

    function close() {
        GlobalStates.launchpadOpen = false;
    }

    // The app is started immediately and the overlay lingers a beat, rather
    // than the other way round: delaying execute() to play an animation would
    // make the app genuinely slower to appear. The pause only exists so the
    // click is acknowledged before everything disappears.
    property string launchingId: ""

    Timer {
        id: launchCloseTimer
        interval: 430
        repeat: false
        onTriggered: root.close()
    }

    function launch(entry) {
        if (!entry || root.launchingId.length > 0)
            return;
        root.launchingId = entry.id;
        LaunchpadUsage.record(entry.id);
        entry.execute();
        launchCloseTimer.restart();
    }

    function launchSelected() {
        root.launch(root.apps[root.selectedIndex]);
    }

    // Selection drives the page, not the other way round: arrowing off the
    // edge of a page should carry the view with it.
    function select(index) {
        if (root.apps.length === 0)
            return;
        root.selectedIndex = Math.max(0, Math.min(root.apps.length - 1, index));
        pager.goTo(Math.floor(root.selectedIndex / root.pageSize), true);
    }

    onQueryChanged: {
        root.selectedIndex = 0;
        pager.goTo(0, false);
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Appearance.m3colors.m3background.r, Appearance.m3colors.m3background.g, Appearance.m3colors.m3background.b, 0.62)

        // The backdrop carries the wheel rather than a WheelHandler, because a
        // WheelHandler filters on a single `orientation` and throws away any
        // event with no delta along it. The default is vertical, so a two-finger
        // swipe straight across the pad - the whole point of the gesture - was
        // dropped before it ever reached us, and only a swipe with enough
        // up-and-down in it to register on the other axis got through. A
        // MouseArea takes both axes, and the scroll phases along with them.
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
            onWheel: event => root.handleScroll(event)
        }
    }

    // A wheel notch is 120. High-resolution wheels send fractions of one, so
    // they are added up rather than counted.
    property real notchAccum: 0

    Timer {
        id: notchIdle
        interval: 300
        repeat: false
        // Left to itself a part-notch never expires, and the next nudge an hour
        // later inherits it and turns the page on its own.
        onTriggered: root.notchAccum = 0
    }

    // A touchpad and a mouse wheel want opposite things from the same event, so
    // they are told apart and handled separately. The scroll phase is what tells
    // them apart: Wayland tags a touchpad's stream with one and a mouse wheel's
    // with none. That beats looking for a pixel delta, because the event that
    // reports the fingers lifting carries a phase and no delta at all - reading
    // it as a wheel was why a swipe had to time out before it settled.
    function handleScroll(event) {
        if (event.phase === Qt.NoScrollPhase) {
            const notch = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
            notchIdle.restart();
            const [steps, rest] = Paging.notchSteps(root.notchAccum + notch);
            root.notchAccum = rest;
            if (steps !== 0)
                pager.goTo(pager.currentPage + steps, true);
            return;
        }

        if (event.phase === Qt.ScrollBegin) {
            pager.beginDrag();
            return;
        }

        if (event.phase === Qt.ScrollEnd) {
            pager.endDrag();
            return;
        }

        // Sideways if there is any, otherwise read an up-and-down swipe as
        // paging too - the grid has nothing to scroll vertically. Both signs are
        // the compositor's, unaltered, so the grid follows the fingers under the
        // natural scrolling the touchpad is configured for.
        const dx = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.pixelDelta.y;
        pager.dragBy(dx * pager.swipeGain, true);
    }

    Item {
        id: stage
        anchors.fill: parent

        opacity: root.active ? 1 : 0
        scale: root.active ? 1 : 1.08
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }

        Rectangle {
            id: searchField
            anchors {
                top: parent.top
                topMargin: root.barInset + 26
                horizontalCenter: parent.horizontalCenter
            }
            width: 340
            height: 38
            radius: Appearance.rounding.full
            color: Qt.rgba(Appearance.colors.colLayer1.r, Appearance.colors.colLayer1.g, Appearance.colors.colLayer1.b, 0.7)

            MaterialSymbol {
                id: searchIcon
                anchors {
                    left: parent.left
                    leftMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                text: "search"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colSubtext
            }

            StyledTextInput {
                id: searchInput
                anchors {
                    left: searchIcon.right
                    leftMargin: 10
                    right: parent.right
                    rightMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                focus: true
                onTextChanged: root.query = text

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length === 0
                    text: qsTr("Search")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        if (root.query.length > 0)
                            searchInput.text = "";
                        else
                            root.close();
                        event.accepted = true;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.launchSelected();
                        event.accepted = true;
                        break;
                    case Qt.Key_Left:
                        root.select(root.selectedIndex - 1);
                        event.accepted = true;
                        break;
                    case Qt.Key_Right:
                        root.select(root.selectedIndex + 1);
                        event.accepted = true;
                        break;
                    case Qt.Key_Up:
                        root.select(root.selectedIndex - root.columns);
                        event.accepted = true;
                        break;
                    case Qt.Key_Down:
                        root.select(root.selectedIndex + root.columns);
                        event.accepted = true;
                        break;
                    case Qt.Key_PageUp:
                        root.select(root.selectedIndex - root.pageSize);
                        event.accepted = true;
                        break;
                    case Qt.Key_PageDown:
                        root.select(root.selectedIndex + root.pageSize);
                        event.accepted = true;
                        break;
                    case Qt.Key_Home:
                        root.select(0);
                        event.accepted = true;
                        break;
                    case Qt.Key_End:
                        root.select(root.apps.length - 1);
                        event.accepted = true;
                        break;
                    }
                }
            }
        }

        // A plain strip of pages rather than a ListView. A horizontal ListView
        // drops vertical wheel events outright, and StrictlyEnforceRange - the
        // only thing that makes it snap to whole pages - re-snaps the instant
        // contentX is written by hand, so the view cannot be made to follow a
        // gesture. Owning the offset directly is what allows the page to track
        // the fingers and settle where they leave it.
        Item {
            id: pager
            anchors {
                top: searchField.bottom
                topMargin: 22
                bottom: pageDots.top
                bottomMargin: 12
                left: parent.left
                right: parent.right
                leftMargin: 60
                rightMargin: 60
            }
            clip: true

            readonly property real cellWidth: width / root.columns
            readonly property real cellHeight: height / root.rows
            readonly property real iconSize: Math.max(44, Math.min(96, Math.min(cellWidth, cellHeight) * 0.5))

            // Where the strip sits, counted in pages. Fractional mid-gesture,
            // which is what lets the dots and the page loaders track a drag
            // rather than jumping once it ends.
            readonly property real position: width > 0 ? -strip.x / width : 0
            readonly property int visiblePage: Math.max(0, Math.min(root.pageCount - 1, Math.round(position)))
            // Where the strip has settled, or is settling.
            property int currentPage: 0

            readonly property real maxX: 0
            readonly property real minX: -(root.pageCount - 1) * width

            // The pad hands us about 7.5px of scroll for every millimetre of
            // finger, measured, once its own scroll_factor has been applied. A
            // page is most of a screen wide, so tracking that one-to-one would
            // want a swipe several times longer than the pad. At this gain a
            // full page is about 75mm of travel and a page turn about 17mm.
            // This is the number to change if paging feels heavy or twitchy.
            readonly property real swipeGain: 3.2
            // How far past the ends a gesture can pull, and how hard it resists.
            readonly property real rubberBand: 0.32
            // A gesture that ends this far into a page carries over to it...
            readonly property real settleFraction: 0.22
            // ...and so does one still moving this fast, however short it was.
            // This is what makes a quick flick page without covering distance.
            // Above the speed a deliberate, slow drag reaches, or every drag
            // would count as a flick and nothing could be pulled back from.
            readonly property real flickVelocity: 900

            property bool dragging: false
            property real dragStart: 0
            property real velocity: 0
            property real lastX: 0
            property double lastTime: 0

            // A resize - a monitor change, or the bar appearing - must not leave
            // the strip stranded between two pages.
            onWidthChanged: if (!dragging) goTo(currentPage, false)

            function resist(x) {
                return Paging.resist(x, minX, maxX, rubberBand);
            }

            function goTo(page, animate) {
                settleAnim.stop();
                currentPage = Math.max(0, Math.min(root.pageCount - 1, page));
                const dest = -currentPage * width;
                if (!animate || width <= 0) {
                    strip.x = dest;
                    return;
                }
                // Tie the snap to what is left to travel. Finishing the last
                // sliver of a drag with a full-length animation is the thing
                // that reads as lag.
                const remaining = Math.abs(dest - strip.x) / width;
                settleAnim.duration = Math.max(150, Math.min(400, 130 + remaining * 300));
                settleAnim.from = strip.x;
                settleAnim.to = dest;
                settleAnim.start();
            }

            function beginDrag() {
                settleAnim.stop();
                dragging = true;
                dragStart = position;
                velocity = 0;
                lastX = strip.x;
                lastTime = Date.now();
            }

            function dragBy(dx, fromWheel) {
                if (!dragging)
                    beginDrag();
                const now = Date.now();
                const dt = Math.max(1, now - lastTime);
                strip.x = resist(strip.x + dx);
                // Averaged, so one stuttering frame cannot decide on its own
                // whether this counted as a flick.
                velocity = velocity * 0.6 + (-(strip.x - lastX) * 1000 / dt) * 0.4;
                lastX = strip.x;
                lastTime = now;
                if (fromWheel)
                    settleTimer.restart();
            }

            function endDrag() {
                if (!dragging)
                    return;
                dragging = false;
                settleTimer.stop();
                // Fingers resting on the pad still send nothing, so a gap this
                // long means the gesture was over before it was let go.
                if (Date.now() - lastTime > 120)
                    velocity = 0;

                const base = Math.round(dragStart);
                const target = Paging.settleTarget(dragStart, position, velocity, root.pageCount, {
                    settleFraction: settleFraction,
                    flickVelocity: flickVelocity
                });
                // Carry the keyboard selection along, or arrowing after a swipe
                // jumps back to a page that is no longer on screen.
                if (target !== base)
                    root.selectedIndex = Math.min(root.apps.length - 1, target * root.pageSize);
                goTo(target, true);
            }

            // Click-drag and touchscreen swipe, on the same machinery. Scoped to
            // the grid rather than the whole overlay so it cannot swallow a
            // drag-select in the search field. A tile's MouseArea grabs first,
            // but a DragHandler is allowed to take a grab off an Item once it
            // passes the threshold, which is how a swipe that starts on an icon
            // still pages instead of launching it.
            DragHandler {
                id: swipeDrag
                target: null
                xAxis.enabled: true
                yAxis.enabled: false
                // Wider than the default, or a slightly shaky click on a tile
                // turns the page instead of opening the app.
                dragThreshold: 16

                property real previous: 0

                onActiveChanged: {
                    if (active) {
                        pager.beginDrag();
                        previous = centroid.position.x;
                    } else {
                        pager.endDrag();
                    }
                }
                onCentroidChanged: {
                    if (!active)
                        return;
                    pager.dragBy(centroid.position.x - previous, false);
                    previous = centroid.position.x;
                }
            }

            Timer {
                id: settleTimer
                // Only ever reached when the scroll stream stops without a
                // ScrollEnd phase. Short enough to feel like a release, long
                // enough not to cut a slow swipe in half.
                interval: 90
                repeat: false
                onTriggered: pager.endDrag()
            }

            NumberAnimation {
                id: settleAnim
                target: strip
                property: "x"
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }

            Item {
                id: strip
                width: pager.width * root.pageCount
                height: pager.height

                Repeater {
                    model: root.pageCount

                    delegate: Item {
                        id: page
                        required property int index
                        x: index * pager.width
                        width: pager.width
                        height: pager.height

                        // Only the page in view and its neighbours are built. A
                        // machine with a few hundred apps would otherwise pay
                        // for every icon on every page the moment it opens, and
                        // one page either side is all a gesture can reveal.
                        readonly property bool near: Math.abs(index - pager.visiblePage) <= 1

                        // Anchored to the top rather than centred so a partly
                        // filled page - the last one, or a short set of search
                        // results - keeps its first row where every full page
                        // puts it.
                        Grid {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            columns: root.columns

                            Repeater {
                                model: page.near ? root.apps.slice(page.index * root.pageSize, (page.index + 1) * root.pageSize) : []

                                delegate: LaunchpadItem {
                                    required property var modelData
                                    required property int index

                                    entry: modelData
                                    width: pager.cellWidth
                                    height: pager.cellHeight
                                    iconSize: pager.iconSize
                                    launching: root.launchingId.length > 0 && root.launchingId === modelData.id
                                    dimmed: root.launchingId.length > 0 && root.launchingId !== modelData.id
                                    selected: root.selectedIndex === page.index * root.pageSize + index
                                    onActivated: root.launch(modelData)
                                    onHovered: root.selectedIndex = page.index * root.pageSize + index
                                }
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            anchors.centerIn: pager
            visible: root.apps.length === 0
            text: qsTr("No apps match “%1”").arg(root.query)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.normal
        }

        Row {
            id: pageDots
            anchors {
                bottom: parent.bottom
                bottomMargin: 34
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 10
            visible: root.pageCount > 1

            Repeater {
                model: root.pageCount

                delegate: Rectangle {
                    required property int index
                    width: 8
                    height: 8
                    radius: 4
                    color: Appearance.colors.colOnLayer0
                    // Read off the live position rather than the settled page,
                    // so the dots hand over gradually as the grid is dragged and
                    // the gesture has something answering back. Clamped to one
                    // page of distance, so only the pair either side move.
                    opacity: 0.35 + 0.55 * Math.max(0, 1 - Math.abs(pager.position - index))

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pager.goTo(index, true)
                    }
                }
            }
        }
    }
}
