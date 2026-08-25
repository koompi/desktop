// L8 check: qs -p .work/tmp/gamemode.qml
// GameMode.qml's shape: a base type declares `toggled`, the instance binds
// `toggled: toggled`. Compared with an instance that leaves it alone.
import QtQuick
import Quickshell
ShellRoot {
  component Base: QtObject {
    property bool toggled
  }
  Base {
    id: selfBound
    toggled: toggled
  }
  Base {
    id: plain
  }
  Component.onCompleted: {
    console.log("self-bound toggled =", selfBound.toggled, "| plain default =", plain.toggled)
    selfBound.toggled = true
    console.log("after assignment, self-bound toggled =", selfBound.toggled)
    Qt.quit()
  }
}
