import qs.modules.common
import qs.modules.koompi.sidebarLeft.aiChat.memory
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Everything the assistant remembers, in one place: grouped by what the entry
 * is for, editable, deletable, searchable through the daemon's own `recall`.
 *
 * Embeddable on purpose - the sidebar, the full window and the standalone
 * browser window all mount this same item.
 */
Item {
    id: root

    property bool active: true

    property var entries: []
    property var pruneCandidates: []
    property var pruneReasons: ({})
    property var statsBody: null
    property string statsRaw: ""
    property string status: ""
    property bool loading: false

    property string searchQuery: ""
    property var searchResults: null // null while not searching

    readonly property int shownCount: root.searchResults !== null ? root.searchResults.length : root.entries.length

    // Flat model: every row carries the uppercase group label when it opens a
    // group, so one delegate draws both the section head and the entry.
    readonly property var rows: {
        if (root.searchResults !== null) {
            return root.searchResults.map((entry, index) => ({
                "groupLabel": index === 0 ? Translation.tr("BEST MATCHES") : "",
                "entry": entry,
                "reason": root.pruneReasons[entry.id] ?? "",
                "score": entry.score ?? NaN
            }));
        }
        const out = [];
        for (let g = 0; g < MemoryService.groupOrder.length; g++) {
            const group = MemoryService.groupOrder[g];
            let first = true;
            for (let i = 0; i < root.entries.length; i++) {
                const entry = root.entries[i];
                if (MemoryService.groupOf(entry.mtype) !== group) continue;
                out.push({
                    "groupLabel": first ? group : "",
                    "entry": entry,
                    "reason": root.pruneReasons[entry.id] ?? "",
                    "score": NaN
                });
                first = false;
            }
        }
        return out;
    }

    function refresh() {
        if (!MemoryService.enabled) {
            root.status = Translation.tr("Memory is switched off in settings.");
            return;
        }
        root.status = "";
        root.loading = true;
        MemoryService.list(500, (response, error) => {
            root.loading = false;
            if (!response) {
                root.status = error;
                return;
            }
            root.entries = response.results ?? [];
        });
        MemoryService.stats((response, error) => {
            if (!response) return;
            root.statsBody = response;
            root.statsRaw = JSON.stringify(response);
        });
        // The reason each row is junk comes from the daemon's own rule, not from
        // a copy of its rules living here.
        MemoryService.prune(true, (response, error) => {
            if (!response) return;
            const candidates = response.candidates ?? [];
            const reasons = ({});
            for (let i = 0; i < candidates.length; i++) reasons[candidates[i].id] = candidates[i].reason;
            root.pruneCandidates = candidates;
            root.pruneReasons = reasons;
        });
    }

    function runSearch() {
        const query = root.searchQuery.trim();
        if (query.length === 0) {
            root.searchResults = null;
            return;
        }
        MemoryService.recall(query, 20, (results, error) => {
            if (!results) {
                root.status = error;
                return;
            }
            root.searchResults = results;
            root.status = "";
        }, "browse");
    }

    // Owned by the browser, not by the dialog that asks for them: a dialog's
    // Loader unloads on the same click, taking its callbacks with it.
    function archiveTranscript() {
        MemoryService.prune(false, (response, error) => {
            root.searchResults = null;
            root.refresh();
            root.status = response ? Translation.tr("Archived %1 entries.").arg(response.archived) : error;
        });
    }

    function deleteEverything() {
        root.status = Translation.tr("Deleting\u2026");
        MemoryService.clearAll((count, error) => {
            root.searchResults = null;
            root.refresh();
            root.status = count === null ? error : Translation.tr("Deleted %1 memories.").arg(count);
        });
    }

    onActiveChanged: if (root.active) root.refresh()
    Component.onCompleted: if (root.active) root.refresh()

    Connections {
        target: MemoryService
        function onReadyChanged() {
            if (MemoryService.ready && root.active) root.refresh();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle { // header
                Layout.fillWidth: true
                implicitHeight: headerLayout.implicitHeight + Appearance.spacing.normal * 2
                color: Appearance.colors.colLayer2
                topLeftRadius: Appearance.rounding.normal
                topRightRadius: Appearance.rounding.normal

                ColumnLayout {
                    id: headerLayout
                    anchors {
                        fill: parent
                        margins: Appearance.spacing.normal
                    }
                    spacing: Appearance.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Appearance.spacing.small

                        MaterialSymbol {
                            text: "neurology"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.shownCount === 1 ? Translation.tr("AI Memory — 1 entry") : Translation.tr("AI Memory — %1 entries").arg(root.shownCount)
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }

                        IconToolbarButton {
                            Layout.fillHeight: false
                            implicitHeight: 30
                            text: "refresh"
                            onClicked: root.refresh()
                            StyledToolTip { text: Translation.tr("Reload from the daemon") }
                        }

                        IconToolbarButton {
                            Layout.fillHeight: false
                            implicitHeight: 30
                            text: "cognition"
                            onClicked: {
                                root.status = Translation.tr("Consolidating…");
                                MemoryService.consolidate(200, (response, error) => {
                                    if (!response) {
                                        root.status = error;
                                        return;
                                    }
                                    const added = response.added ?? [];
                                    root.refresh();
                                    root.status = added.length > 0 ? Translation.tr("Learned: %1").arg(added.join(" · ")) : Translation.tr("Read %1 event(s), nothing worth keeping.").arg(response.marked ?? 0);
                                });
                            }
                            StyledToolTip { text: Translation.tr("Consolidate the event log now") }
                        }

                        IconToolbarButton {
                            Layout.fillHeight: false
                            implicitHeight: 30
                            text: "mop"
                            enabled: root.pruneCandidates.length > 0
                            onClicked: pruneDialog.shown = true
                            StyledToolTip { text: Translation.tr("Clean up imported transcript (%1)").arg(root.pruneCandidates.length) }
                        }

                        DialogButton {
                            buttonText: Translation.tr("Clear all")
                            colText: Appearance.colors.colError
                            enabled: root.entries.length > 0
                            onClicked: clearDialog.shown = true
                        }
                    }

                    ToolbarTextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: 34
                        placeholderText: Translation.tr("Search memories…")
                        onTextChanged: {
                            root.searchQuery = text;
                            if (text.trim().length === 0) {
                                root.searchResults = null;
                                searchDebounce.stop();
                                return;
                            }
                            searchDebounce.restart();
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                searchDebounce.stop();
                                root.runSearch();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                searchField.text = "";
                                event.accepted = true;
                            }
                        }

                        Timer {
                            id: searchDebounce
                            interval: Appearance.animation.elementMoveFast.duration
                            onTriggered: root.runSearch()
                        }
                    }

                    StyledText {
                        visible: root.status.length > 0
                        Layout.fillWidth: true
                        text: root.status
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StyledListView {
                    id: listView
                    anchors {
                        fill: parent
                        margins: Appearance.spacing.normal
                    }
                    clip: true
                    spacing: Appearance.spacing.small
                    visible: root.rows.length > 0
                    model: root.rows

                    delegate: ColumnLayout {
                        id: delegateRoot
                        required property var modelData
                        width: listView.width
                        spacing: Appearance.spacing.hairline

                        StyledText {
                            visible: delegateRoot.modelData.groupLabel.length > 0
                            Layout.topMargin: Appearance.spacing.small
                            text: delegateRoot.modelData.groupLabel
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                            color: Appearance.colors.colSubtext
                        }

                        MemoryEntry {
                            Layout.fillWidth: true
                            entry: delegateRoot.modelData.entry
                            rejectReason: delegateRoot.modelData.reason
                            score: delegateRoot.modelData.score
                            onDeleteRequested: {
                                MemoryService.forget(entry.id, (response, error) => {
                                    root.searchResults = null;
                                    root.refresh();
                                    root.status = response ? Translation.tr("Deleted memory %1.").arg(entry.id) : error;
                                });
                            }
                            onEditAccepted: text => {
                                MemoryService.edit(entry.id, text, entry.mtype, entry.tags ?? [], "user:edit", (response, error) => {
                                    root.searchResults = null;
                                    root.refresh();
                                    root.status = response ? Translation.tr("Rewrote memory %1 as %2.").arg(entry.id).arg(response.memory_id) : error;
                                });
                            }
                        }
                    }
                }

                PagePlaceholder {
                    shown: root.rows.length === 0
                    icon: root.searchResults !== null ? "search_off" : "neurology"
                    title: root.searchResults !== null ? Translation.tr("Nothing matched") : Translation.tr("Nothing remembered yet")
                    description: root.searchResults !== null ? Translation.tr("No memory scored high enough for that query.") : Translation.tr("Tell the assistant something durable about yourself and it will land here.")
                }
            }

            Rectangle { // footer
                Layout.fillWidth: true
                implicitHeight: footerLayout.implicitHeight + Appearance.spacing.normal * 2
                color: Appearance.colors.colLayer2
                bottomLeftRadius: Appearance.rounding.normal
                bottomRightRadius: Appearance.rounding.normal

                RowLayout {
                    id: footerLayout
                    anchors {
                        fill: parent
                        margins: Appearance.spacing.normal
                    }
                    spacing: Appearance.spacing.small

                    MaterialSymbol {
                        text: "lock"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Memory is stored locally · never sent to the cloud")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: root.statsBody ? Translation.tr("%1 live · %2 · %3-dim").arg(root.statsBody.count).arg(root.statsBody.provider).arg(root.statsBody.dim) : Translation.tr("stats unavailable")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2

                        MouseArea {
                            id: statsHover
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        StyledToolTip {
                            text: root.statsRaw
                            // A plain Text has no `hovered`, and the widget reads
                            // that as "always shown".
                            extraVisibleCondition: statsHover.containsMouse
                        }
                    }
                }
            }
        }
    }

    // A WindowDialog sizes itself to its content the moment it exists, so an
    // unopened one sits on the panel as a grey slab. It is built when asked for.
    component ConfirmDialogLoader: Loader {
        id: dialogLoader
        property bool shown: false
        anchors.fill: parent
        active: shown
        onActiveChanged: if (active) {
            item.show = true;
            item.forceActiveFocus();
        }
        Connections {
            target: dialogLoader.item
            function onDismiss() {
                dialogLoader.shown = false;
            }
        }
    }

    ConfirmDialogLoader {
        id: clearDialog
        sourceComponent: WindowDialog {
            backgroundWidth: 420
            backgroundHeight: 240

            WindowDialogTitle {
                Layout.fillWidth: true
                text: Translation.tr("Delete every memory?")
            }

            WindowDialogParagraph {
                Layout.fillWidth: true
                text: root.entries.length === 1 ? Translation.tr("The one entry goes, including anything you told the assistant about yourself. This cannot be undone.") : Translation.tr("All %1 entries go, including anything you told the assistant about yourself. This cannot be undone.").arg(root.entries.length)
            }

            WindowDialogButtonRow {
                Layout.fillWidth: true

                Item { Layout.fillWidth: true }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: clearDialog.shown = false
                }

                DialogButton {
                    buttonText: Translation.tr("Delete all")
                    colText: Appearance.colors.colError
                    onClicked: {
                        clearDialog.shown = false;
                        root.deleteEverything();
                    }
                }
            }
        }
    }

    ConfirmDialogLoader {
        id: pruneDialog
        sourceComponent: WindowDialog {
            backgroundWidth: 560
            backgroundHeight: 520

            WindowDialogTitle {
                Layout.fillWidth: true
                text: Translation.tr("Retire imported transcript?")
            }

            WindowDialogParagraph {
                Layout.fillWidth: true
                text: Translation.tr("%1 entries were copied out of the chat log by the old consolidator, so the assistant is being fed its own replies as facts. Archiving hides them from recall; the rows stay on disk.").arg(root.pruneCandidates.length)
            }

            StyledFlickable {
                id: candidateFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: candidateColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: candidateColumn
                    width: candidateFlickable.width
                    spacing: Appearance.spacing.small

                    Repeater {
                        model: root.pruneCandidates

                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: `${modelData.id}  ${modelData.text}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.reason
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colError
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }
                }
            }

            WindowDialogButtonRow {
                Layout.fillWidth: true

                Item { Layout.fillWidth: true }

                DialogButton {
                    buttonText: Translation.tr("Keep them")
                    onClicked: pruneDialog.shown = false
                }

                DialogButton {
                    buttonText: Translation.tr("Archive them")
                    colText: Appearance.colors.colError
                    onClicked: {
                        pruneDialog.shown = false;
                        root.archiveTranscript();
                    }
                }
            }
        }
    }
}
