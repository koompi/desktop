import "feedbackRules.js" as Rules
import QtQuick

/**
 * The habit table (docs/neuromorphic-memory-design.md:224-247): one row per
 * tool and input pattern, counting what succeeded and what failed. Rows live
 * in `store.procedures`; the keying and the outcome rules are in
 * feedbackRules.js. `engine` is the Ai facade, read for the session id and
 * the approval rule of a tool.
 */
QtObject {
    id: root

    property QtObject engine
    property FeedbackStore store

    function recordProcedures(turn) {
        const calls = turn?.toolCalls ?? [];
        if (calls.length === 0) return;
        const byId = ({});
        for (const result of (turn.toolResults ?? [])) byId[result.toolCallId] = result;

        const rows = root.store.procedures.slice();
        let changed = false;
        for (const call of calls) {
            const name = call?.name ?? "";
            if (name.length === 0) continue;
            const pattern = Rules.procedureKey(name, Rules.callArgs(call));
            const result = byId[call.id ?? ""] ?? null;
            // A call with no result never ran: the user rejected it, or the turn
            // ended first. Neither is evidence about the tool.
            if (!result) continue;
            const outcome = Rules.outcomeOf(name, result.response);
            const index = rows.findIndex(row => row.tool_name === name && row.input_pattern === pattern);
            const base = index >= 0 ? rows[index] : {
                "id": rows.length + 1,
                "tool_name": name,
                "input_pattern": pattern,
                "success_count": 0,
                "failure_count": 0,
                "total_tokens_est": 0,
                "last_used": 0,
                "session_id": "",
                "approved": 0
            };
            const updated = Object.assign({}, base, {
                "success_count": base.success_count + (outcome === "success" ? 1 : 0),
                "failure_count": base.failure_count + (outcome === "failure" ? 1 : 0),
                "total_tokens_est": base.total_tokens_est + Rules.estimateTokens(result.response),
                "last_used": Date.now(),
                "session_id": root.engine?.sessionId ?? "",
                "approved": base.approved || ((root.engine?.approvalOf(name) ?? "never") !== "never" && outcome === "success" ? 1 : 0)
            });
            if (index >= 0) rows[index] = updated; else rows.push(updated);
            changed = true;
        }
        if (!changed) return;
        root.store.procedures = rows;
        root.store.saveProcedures();
    }

    // What a habit is worth, per :239-241: successes against everything tried.
    function actionScore(row) {
        const total = (row?.success_count ?? 0) + (row?.failure_count ?? 0);
        if (total === 0) return 0;
        return row.success_count / total;
    }
}
