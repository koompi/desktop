import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    spacing: Appearance.spacing.small
    // Only the edit button opens the field. An error is usually the network, not
    // the URL, and swapping the events for a paste box reads as "not connected".
    property bool entering: false
    readonly property bool editing: entering

    RowLayout {
        Layout.fillWidth: true
        // A nested layout stretches by default, which left the list one row tall.
        Layout.fillHeight: false
        spacing: Appearance.spacing.small

        MaterialSymbol {
            text: "event"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: GoogleCalendar.connected ? Translation.tr("Google Calendar") : Translation.tr("No calendar connected")
        }
        IconToolbarButton {
            visible: GoogleCalendar.connected
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            text: GoogleCalendar.loading ? "sync" : "refresh"
            enabled: !GoogleCalendar.loading
            onClicked: GoogleCalendar.refresh()
            StyledToolTip {
                text: Translation.tr("Refresh")
            }
        }
        IconToolbarButton {
            visible: GoogleCalendar.connected
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            text: "edit"
            onClicked: {
                urlField.text = GoogleCalendar.url;
                root.entering = true;
                urlField.forceActiveFocus();
            }
            StyledToolTip {
                text: Translation.tr("Change calendar URL")
            }
        }
        IconToolbarButton {
            visible: GoogleCalendar.connected
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            text: "link_off"
            onClicked: GoogleCalendar.disconnect()
            StyledToolTip {
                text: Translation.tr("Disconnect")
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: GoogleCalendar.error.length > 0
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.m3colors.m3error
        text: GoogleCalendar.error
    }

    // Not connected: one button, which opens the one field it needs.
    RippleButtonWithIcon {
        Layout.fillWidth: true
        visible: !GoogleCalendar.connected && !root.editing
        materialIcon: "add_link"
        mainText: Translation.tr("Connect Google Calendar")
        onClicked: root.entering = true
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root.editing
        spacing: Appearance.spacing.small

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: Translation.tr("Google Calendar > Settings > your calendar > Secret address in iCal format. Paste it here.")
        }

        MaterialTextField {
            id: urlField
            Layout.fillWidth: true
            placeholderText: Translation.tr("https://calendar.google.com/calendar/ical/.../basic.ics")
            onAccepted: connectButton.clicked()
            Component.onCompleted: text = GoogleCalendar.url
        }

        // Prefill on change, not by binding: clicking Connect takes focus off the
        // field, and a focus-conditional binding wiped what was just pasted.
        // onCompleted is too early - Persistent may not have read states.json yet.
        Connections {
            target: GoogleCalendar
            function onUrlChanged() {
                urlField.text = GoogleCalendar.url;
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small
            Item {
                Layout.fillWidth: true
            }
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: root.entering = false
            }
            DialogButton {
                id: connectButton
                buttonText: GoogleCalendar.connected ? Translation.tr("Save") : Translation.tr("Connect")
                onClicked: if (GoogleCalendar.connect(urlField.text)) root.entering = false
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: GoogleCalendar.connected && GoogleCalendar.events.length === 0 && !GoogleCalendar.loading && GoogleCalendar.error.length === 0
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: Translation.tr("Nothing in the next %1 days").arg(GoogleCalendar.daysAhead)
    }

    StyledListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: GoogleCalendar.connected && GoogleCalendar.events.length > 0
        clip: true
        spacing: Appearance.spacing.hairline
        // The whole list arrives at once, and animating contentY through that
        // left the view parked mid-item, clipping the first event's title.
        scrollAnimation: false
        model: GoogleCalendar.events

        delegate: RowLayout {
            required property var modelData
            width: ListView.view.width
            spacing: Appearance.spacing.normal

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 3
                radius: 2
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: modelData.summary
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: {
                        const d = modelData.start.toLocaleDateString(Qt.locale(), "ddd d MMM");
                        if (modelData.allDay)
                            return Translation.tr("%1 - all day").arg(d);
                        const t = modelData.start.toLocaleTimeString(Qt.locale(), "hh:mm");
                        return modelData.location.length > 0 ? `${d} ${t} - ${modelData.location}` : `${d} ${t}`;
                    }
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
        visible: !(GoogleCalendar.connected && GoogleCalendar.events.length > 0)
    }
}
