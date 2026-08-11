pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One conversation on disk: what it was about, when it last moved, how big it
// is, and the two destructive controls behind their own confirmation.
RippleButton {
    id: root

    property var thread: null
    property bool current: false
    property bool protectedThread: false
    property bool renaming: false
    property bool confirmingDelete: false

    signal resumeRequested
    signal renameAccepted(string title)
    signal deleteRequested

    readonly property string title: (root.thread?.title ?? "").length > 0 ? root.thread.title : root.thread?.id ?? ""
    readonly property int messageCount: root.thread?.messageCount ?? 0

    function beginRename() {
        if (root.protectedThread)
            return;
        renameField.text = root.title;
        root.renaming = true;
        renameField.forceActiveFocus();
        renameField.selectAll();
    }

    function relativeWhen(timestamp) {
        const stamp = timestamp ?? 0;
        if (stamp <= 0)
            return Translation.tr("never saved");
        const seconds = Math.max(0, Math.round((Date.now() - stamp) / 1000));
        if (seconds < 60)
            return Translation.tr("just now");
        if (seconds < 3600)
            return Translation.tr("%1 min ago").arg(Math.floor(seconds / 60));
        if (seconds < 86400)
            return Translation.tr("%1 h ago").arg(Math.floor(seconds / 3600));
        if (seconds < 604800)
            return Translation.tr("%1 d ago").arg(Math.floor(seconds / 86400));
        return new Date(stamp).toLocaleDateString(Qt.locale());
    }

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + Appearance.spacing.normal * 2
    buttonRadius: Appearance.rounding.small
    colBackground: root.current ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
    colBackgroundHover: root.current ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: Translation.tr("Thread %1, %2, %3 messages").arg(root.title).arg(root.relativeWhen(root.thread?.updatedAt)).arg(root.messageCount)

    onClicked: {
        if (!root.renaming)
            root.resumeRequested();
    }

    Rectangle { // focus ring
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }

    contentItem: RowLayout {
        id: rowLayout
        spacing: Appearance.spacing.normal

        MaterialSymbol {
            Layout.leftMargin: Appearance.spacing.normal
            text: root.protectedThread ? "shield_lock" : (root.current ? "forum" : "chat_bubble")
            iconSize: Appearance.font.pixelSize.huge
            color: root.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.hairline

            StyledText {
                visible: !root.renaming
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }

            ToolbarTextField {
                id: renameField
                visible: root.renaming
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 36
                placeholderText: Translation.tr("Name this conversation")

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.renaming = false;
                        root.renameAccepted(renameField.text);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.renaming = false;
                        event.accepted = true;
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.protectedThread
                    ? Translation.tr("%1 · %2 messages · read-only").arg(root.relativeWhen(root.thread?.updatedAt)).arg(root.messageCount)
                    : Translation.tr("%1 · %2 messages · session %3").arg(root.relativeWhen(root.thread?.updatedAt)).arg(root.messageCount).arg(root.thread?.sessionId ?? "—")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.current ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }

        StyledText {
            visible: root.confirmingDelete
            text: Translation.tr("Delete for good?")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
        }

        IconToolbarButton {
            visible: root.confirmingDelete
            Layout.fillHeight: false
            implicitHeight: 30
            text: "check"
            colText: Appearance.colors.colError
            onClicked: {
                root.confirmingDelete = false;
                root.deleteRequested();
            }
            Accessible.name: Translation.tr("Confirm delete")
        }

        IconToolbarButton {
            visible: root.confirmingDelete
            Layout.fillHeight: false
            implicitHeight: 30
            text: "close"
            onClicked: root.confirmingDelete = false
            Accessible.name: Translation.tr("Keep it")
        }

        IconToolbarButton {
            visible: !root.confirmingDelete && !root.protectedThread
            Layout.fillHeight: false
            implicitHeight: 30
            text: "edit"
            onClicked: root.beginRename()
            Accessible.name: Translation.tr("Rename")
            StyledToolTip {
                text: Translation.tr("Rename (F2)")
            }
        }

        IconToolbarButton {
            visible: !root.confirmingDelete && !root.protectedThread
            Layout.fillHeight: false
            Layout.rightMargin: Appearance.spacing.normal
            implicitHeight: 30
            text: "delete"
            colText: Appearance.colors.colError
            onClicked: root.confirmingDelete = true
            Accessible.name: Translation.tr("Delete")
            StyledToolTip {
                text: Translation.tr("Delete (Del)")
            }
        }
    }
}
