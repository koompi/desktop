pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell
import QtQuick

/**
 * What is going into the next turn, and what the user has taken out of it.
 *
 * A singleton because a drop has to outlive the window: the content unloads on
 * close and the suppression must not go with it. The engine rebuilds
 * `Ai.recalledMemories` from a fresh recall on every send, so a drop cannot be a
 * one-off edit of that string - it is re-applied whenever the string changes,
 * through the facade's own formatter.
 */
Singleton {
    id: root

    property var droppedMemoryIds: []
    property real chatScrollY: -1
    property int currentPane: 0

    // The same divisor Conversation measures the context with, calibrated there
    // against real prompt_tokens.
    readonly property real charsPerToken: 3.6

    function tokensFor(chars) {
        return Math.round((chars ?? 0) / root.charsPerToken);
    }

    function firstLine(text) {
        const lines = String(text ?? "").split("\n").map(line => line.trim()).filter(line => line.length > 0);
        return lines.length > 0 ? lines[0] : "";
    }

    function isDropped(memoryId) {
        return root.droppedMemoryIds.indexOf(memoryId) >= 0;
    }

    function dropMemory(memoryId) {
        if (root.isDropped(memoryId))
            return;
        root.droppedMemoryIds = [...root.droppedMemoryIds, memoryId];
        root.enforce();
    }

    function restoreMemory(memoryId) {
        root.droppedMemoryIds = root.droppedMemoryIds.filter(id => id !== memoryId);
        root.enforce();
    }

    function restoreAll() {
        root.droppedMemoryIds = [];
        root.enforce();
    }

    property bool _rewriting: false
    // Set while the engine has emptied the block for a fresh recall and that
    // recall has not landed. Rebuilding from the previous recall in that window
    // would hand a request that times out last turn's memories.
    property bool _engineCleared: true

    // The block is always the last recall minus the drops, so a memory put back
    // returns to the next request now, not after the next recall.
    function enforce() {
        if (root._rewriting || root._engineCleared)
            return;
        const recalled = MemoryService.lastRecall ?? [];
        if (recalled.length === 0)
            return;
        const kept = recalled.filter(memory => !root.isDropped(memory.id));
        const block = Ai.formatMemories(kept);
        if (block === Ai.recalledMemories)
            return;
        root._rewriting = true;
        Ai.recalledMemories = block;
        root._rewriting = false;
        console.log(`[intelligence] ${recalled.length - kept.length} memor(ies) held out of the next request: ${root.droppedMemoryIds.join(", ")}`);
    }

    Connections {
        target: Ai
        function onRecalledMemoriesChanged() {
            if (!root._rewriting)
                root._engineCleared = (Ai.recalledMemories ?? "").length === 0;
            root.enforce();
        }
    }

    /* ---- what the next turn will carry ---- */

    readonly property string toolKind: "tool"

    function kindOfTool(name) {
        switch (name) {
        case "search_web":
        case "fetch_url":
            return "web";
        case "ask_agent":
            return "agent";
        case "recall":
        case "remember":
            return "memory";
        default:
            return "file";
        }
    }

    // Every item the next request body will carry, typed, sized and sourced.
    // `chars` is what it costs; `dropped` rows cost nothing because the engine
    // will not be given them.
    readonly property var contextItems: {
        const items = [];

        const recalled = MemoryService.lastRecall ?? [];
        const memoryBlock = Ai.recalledMemories ?? "";
        const prompt = Ai.systemPrompt ?? "";
        items.push({
            "key": "prompt",
            "type": "prompt",
            "name": Translation.tr("System prompt"),
            "detail": Translation.tr("who the assistant is, this machine, the tool rules"),
            "excerpt": root.firstLine(prompt),
            "chars": Math.max(0, prompt.length - memoryBlock.length),
            "score": NaN,
            "droppable": false,
            "dropped": false,
            "memoryId": -1,
            "messageIndex": -1
        });

        for (let i = 0; i < recalled.length; i++) {
            const memory = recalled[i];
            const dropped = root.isDropped(memory.id);
            items.push({
                "key": `memory-${memory.id}`,
                "type": "memory",
                "name": memory.text ?? "",
                "detail": Translation.tr("%1 · strength %2").arg(memory.mtype ?? "memory").arg((memory.strength ?? 0).toFixed(2)),
                "excerpt": root.firstLine(memory.text),
                "chars": dropped ? 0 : (memory.text ?? "").length + 3,
                "score": memory.score ?? NaN,
                "droppable": true,
                "dropped": dropped,
                "memoryId": memory.id,
                "messageIndex": -1
            });
        }

        const attached = Ai.pendingFilePath ?? "";
        if (attached.length > 0) {
            items.push({
                "key": `file-${attached}`,
                "type": "file",
                "name": attached.split("/").pop(),
                "detail": attached,
                "excerpt": Translation.tr("attached to the next message"),
                "chars": 0,
                "score": NaN,
                "droppable": true,
                "dropped": false,
                "memoryId": -1,
                "messageIndex": -2
            });
        }

        const ids = Ai.messageIDs ?? [];
        let turnChars = 0;
        let turnCount = 0;
        for (let i = 0; i < ids.length; i++) {
            const message = Ai.messageByID[ids[i]];
            if (!message)
                continue;
            if (message.role === Ai.interfaceRole)
                continue;
            const body = message.rawContent ?? message.content ?? "";
            const isToolResult = message.role === "tool" || (message.toolCallId ?? "").length > 0 || (message.functionResponse ?? "").length > 0;
            if (!isToolResult) {
                turnChars += body.length;
                turnCount++;
                continue;
            }
            const name = message.functionName ?? "tool";
            items.push({
                "key": `tool-${ids[i]}`,
                "type": root.kindOfTool(name),
                "name": name,
                "detail": Translation.tr("tool result in the transcript"),
                "excerpt": root.firstLine(message.functionResponse ?? body),
                "chars": (message.functionResponse ?? body).length,
                "score": NaN,
                "droppable": true,
                "dropped": false,
                "memoryId": -1,
                "messageIndex": i
            });
        }

        if (turnCount > 0) {
            items.push({
                "key": "turns",
                "type": "conversation",
                "name": turnCount === 1 ? Translation.tr("1 conversation turn") : Translation.tr("%1 conversation turns").arg(turnCount),
                "detail": Translation.tr("everything said so far in this thread"),
                "excerpt": "",
                "chars": turnChars,
                "score": NaN,
                "droppable": false,
                "dropped": false,
                "memoryId": -1,
                "messageIndex": -1
            });
        }

        return items;
    }

    readonly property int contextChars: root.contextItems.reduce((sum, item) => sum + (item.dropped ? 0 : item.chars), 0)
    readonly property int contextTokens: root.tokensFor(root.contextChars)
    readonly property int contextWindow: Ai.contextWindow > 0 ? Ai.contextWindow : 0
    readonly property real contextFraction: root.contextWindow > 0 ? Math.min(1, root.contextTokens / root.contextWindow) : 0

    // What the newest finished answer actually rested on, in the shell-wide
    // source shape J02, J05 and J06 all speak.
    readonly property var lastAnswerSources: {
        const ids = Ai.messageIDs ?? [];
        for (let i = ids.length - 1; i >= 0; i--) {
            const message = Ai.messageByID[ids[i]];
            if (message?.role !== "assistant")
                continue;
            if ((message.toolCallId ?? "").length > 0 || (message.functionResponse ?? "").length > 0)
                continue;
            return message.sources ?? [];
        }
        return [];
    }

    function dropItem(item) {
        if (!item || !item.droppable)
            return;
        if (item.memoryId >= 0) {
            root.dropMemory(item.memoryId);
            return;
        }
        if (item.messageIndex === -2) {
            Ai.pendingFilePath = "";
            return;
        }
        if (item.messageIndex >= 0) {
            console.log(`[intelligence] dropping ${item.name} (${item.chars} chars) from the context`);
            Ai.removeMessage(item.messageIndex);
        }
    }
}
