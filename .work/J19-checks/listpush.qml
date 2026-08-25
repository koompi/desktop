import QtQuick
import Quickshell
ShellRoot {
  id: r
  property list<string> a: []
  property list<var> b: []
  property var c: []
  property list<point> d: []
  property bool open: a
  property bool inc: a.includes("x")
  onAChanged: console.log("a changed ->", JSON.stringify(a))
  onBChanged: console.log("b changed ->", JSON.stringify(b))
  onCChanged: console.log("c changed ->", JSON.stringify(c))
  onDChanged: console.log("d changed ->", d.length)
  onIncChanged: console.log("inc changed ->", inc)
  Component.onCompleted: {
    console.log("bool coercion of empty list<string>:", open)
    a.push("x"); console.log("after a.push: len", a.length, "open", open, "inc", inc)
    b.push({t:1}); console.log("after b.push: len", b.length)
    b.splice(0,1); console.log("after b.splice: len", b.length)
    b.push({t:2}); b[0].t = 9; console.log("after b[0].t=9:", JSON.stringify(b))
    c.push(1); console.log("after c.push: len", c.length)
    d.push(Qt.point(1,2)); console.log("after d.push: len", d.length)
    Qt.quit()
  }
}
