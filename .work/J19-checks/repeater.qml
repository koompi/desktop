import QtQuick
import QtQml
import Quickshell
import Quickshell.Io
ShellRoot {
  id: r
  property list<string> open: ["a", "b"]
  property list<string> pinned: []
  JsonAdapter {
    id: adapter
    property list<var> toggles: [{ type: "x", size: 1 }, { type: "y", size: 2 }]
    onAdapterUpdated: console.log("adapterUpdated ->", JSON.stringify(toggles))
  }
  Instantiator {
    model: ScriptModel {
      values: r.open.map(id => ({ identifier: id }))
      objectProp: "identifier"
    }
    delegate: QtObject {
      id: w
      required property var modelData
      readonly property string identifier: modelData.identifier
      property bool coerced: r.open
      property bool member: r.open.includes(identifier)
      property bool actuallyPinned: member
      onActuallyPinnedChanged: {
        console.log(identifier, "actuallyPinned ->", actuallyPinned)
        if (actuallyPinned) r.pinned.push(identifier)
        else r.pinned = r.pinned.filter(x => x !== identifier)
      }
      Component.onCompleted: { console.log(identifier, "completed; coerced =", coerced, "member =", member); if (actuallyPinned) r.pinned.push(identifier) }
      Component.onDestruction: console.log(identifier, "destroyed; pinned now", JSON.stringify(r.pinned))
    }
  }
  Component.onCompleted: {
    console.log("pinned at start:", JSON.stringify(r.pinned))
    r.open = r.open.filter(x => x !== "a")
    console.log("after close a: pinned =", JSON.stringify(r.pinned))
    const list = adapter.toggles
    list.splice(0, 1)
    console.log("after splice via local ref:", JSON.stringify(adapter.toggles))
    list[0].size = 3 - list[0].size
    console.log("after element write via local ref:", JSON.stringify(adapter.toggles))
    Qt.callLater(() => { console.log("later: pinned =", JSON.stringify(r.pinned)); Qt.quit() })
  }
}
