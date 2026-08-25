// L14 check: qs -p .work/tmp/l14.qml
// IntelligenceContext's drop/restore/enforce logic, verbatim, over stubs for
// ai (recalledMemories, formatMemories) and memoryService (lastRecall), driven
// the way Requester drives them: clear, recall lands, user drops, user restores.
import QtQuick
import Quickshell
ShellRoot {
  id: r
  QtObject {
    id: ai
    property string recalledMemories: ""
    function formatMemories(results) {
      if (!results || results.length === 0) return "";
      return "\n## What you remember\n" + results.map(m => `- ${m.text}`).join("\n") + "\n";
    }
  }
  QtObject {
    id: memoryService
    property var lastRecall: []
  }
  QtObject {
    id: ctx
    property var droppedMemoryIds: []
    function isDropped(memoryId) { return droppedMemoryIds.indexOf(memoryId) >= 0; }
    function dropMemory(memoryId) { if (isDropped(memoryId)) return; droppedMemoryIds = [...droppedMemoryIds, memoryId]; enforce(); }
    function restoreMemory(memoryId) { droppedMemoryIds = droppedMemoryIds.filter(id => id !== memoryId); enforce(); }
    function restoreAll() { droppedMemoryIds = []; enforce(); }
    property bool _rewriting: false
    property bool _engineCleared: true
    function enforce() {
      if (_rewriting || _engineCleared) return;
      const recalled = memoryService.lastRecall ?? [];
      if (recalled.length === 0) return;
      const kept = recalled.filter(memory => !isDropped(memory.id));
      const block = ai.formatMemories(kept);
      if (block === ai.recalledMemories) return;
      _rewriting = true;
      ai.recalledMemories = block;
      _rewriting = false;
    }
    property Connections c: Connections {
      target: ai
      function onRecalledMemoriesChanged() {
        if (!ctx._rewriting) ctx._engineCleared = (ai.recalledMemories ?? "").length === 0;
        ctx.enforce();
      }
    }
  }
  function lines() { return ai.recalledMemories.split("\n").filter(l => l.startsWith("- ")).join(" "); }
  Component.onCompleted: {
    let failed = 0;
    function expect(name, got, want) { const ok = got === want; console.log((ok ? "ok   " : "FAIL ") + name + ": " + JSON.stringify(got)); if (!ok) failed++; }
    // Requester: clear, then the recall lands
    ai.recalledMemories = "";
    const results = [{ id: 1, text: "likes tea" }, { id: 2, text: "uses zsh" }];
    memoryService.lastRecall = results;
    ai.recalledMemories = ai.formatMemories(results);
    expect("recall in play", lines(), "- likes tea - uses zsh");
    ctx.dropMemory(1);
    expect("drop 1 leaves", lines(), "- uses zsh");
    ctx.restoreMemory(1);
    expect("restore 1 brings it back at once", lines(), "- likes tea - uses zsh");
    ctx.dropMemory(1); ctx.dropMemory(2);
    expect("drop both empties the block", ai.recalledMemories, "");
    ctx.restoreAll();
    expect("restore all from an empty block", lines(), "- likes tea - uses zsh");
    // Requester clears for the next turn; a restore in that window must not resurrect last turn's block
    ctx.dropMemory(2);
    ai.recalledMemories = "";
    ctx.restoreMemory(2);
    expect("restore while the engine has cleared stays empty", ai.recalledMemories, "");
    const next = [{ id: 3, text: "on holiday" }];
    memoryService.lastRecall = next;
    ai.recalledMemories = ai.formatMemories(next);
    expect("next recall lands intact", lines(), "- on holiday");
    console.log(failed ? "FAILED " + failed : "all passed");
    Qt.quit();
  }
}
