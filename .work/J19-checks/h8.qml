// H8 check: qs -p .work/tmp/h8.qml
// Same shape as OverlayContent + StyledOverlayWidget: a delegate per entry of a
// list<string>, a bool gate on that list, registrations kept in a context
// object, and the entry removed while the delegate is pinned. "before" is the
// shipped code; "after" is the fix.
import QtQuick
import QtQml
import Quickshell
ShellRoot {
  id: r
  property list<string> open: ["crosshair", "notes"]

  component Context: QtObject {
    property list<string> pinnedWidgetIdentifiers: []
    function pin(identifier, pin) {
      if (pin) { if (!pinnedWidgetIdentifiers.includes(identifier)) pinnedWidgetIdentifiers.push(identifier) }
      else pinnedWidgetIdentifiers = pinnedWidgetIdentifiers.filter(id => id !== identifier)
    }
  }
  Context { id: before }
  Context { id: after }

  Instantiator {
    model: ScriptModel { values: r.open.map(id => ({ identifier: id })); objectProp: "identifier" }
    delegate: QtObject {
      required property var modelData
      readonly property string identifier: modelData.identifier
      property bool pinned: true
      property bool open: r.open                       // list reference coerced to bool
      property bool actuallyPinned: pinned && open
      onActuallyPinnedChanged: before.pin(identifier, actuallyPinned)
      Component.onCompleted: before.pin(identifier, actuallyPinned)
    }
  }
  Instantiator {
    model: ScriptModel { values: r.open.map(id => ({ identifier: id })); objectProp: "identifier" }
    delegate: QtObject {
      required property var modelData
      readonly property string identifier: modelData.identifier
      property bool pinned: true
      readonly property bool open: r.open.includes(identifier)
      property bool actuallyPinned: pinned && open
      onActuallyPinnedChanged: after.pin(identifier, actuallyPinned)
      Component.onCompleted: after.pin(identifier, actuallyPinned)
      Component.onDestruction: after.pin(identifier, false)
    }
  }

  Component.onCompleted: {
    console.log("pinned while both open  before:", JSON.stringify(before.pinnedWidgetIdentifiers), " after:", JSON.stringify(after.pinnedWidgetIdentifiers))
    r.open = r.open.filter(id => id !== "crosshair")
    Qt.callLater(() => {
      console.log("closed crosshair        before:", JSON.stringify(before.pinnedWidgetIdentifiers), " after:", JSON.stringify(after.pinnedWidgetIdentifiers))
      r.open = []
      console.log("empty list<string> as a bool gate reads:", r.open ? "true" : "false")
      Qt.quit()
    })
  }
}
