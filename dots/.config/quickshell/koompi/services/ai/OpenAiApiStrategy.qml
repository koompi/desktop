import QtQuick

ApiStrategy {
    property bool isReasoning: false
    // tool_calls stream as fragments (name in the first delta, arguments split
    // across many); accumulate per index and emit once on finish_reason/[DONE]
    property var pendingToolCalls: ({})
    property bool toolCallEmitted: false

    // Every call the turn asked for. LiteRT-LM reuses one id for all of them, so the
    // id we answer with is ours: index-suffixed here and echoed back on the result.
    function takeCompletedToolCalls(message) {
        const indices = Object.keys(pendingToolCalls);
        if (indices.length === 0 || toolCallEmitted) return null;
        toolCallEmitted = true;
        const calls = [];
        const wire = [];
        for (let k = 0; k < indices.length; k++) {
            const call = pendingToolCalls[indices[k]];
            if (!call.name || call.name.length === 0) continue;
            let args = {};
            try {
                if (call.arguments && call.arguments.length > 0) args = JSON.parse(call.arguments);
            } catch (e) {
                console.log("[AI] OpenAI: Could not parse tool call arguments: ", e);
            }
            const id = `${(call.id && call.id.length > 0) ? call.id : "call"}_${k}`;
            calls.push({ name: call.name, args: args, id: id });
            wire.push({ "id": id, "name": call.name, "arguments": call.arguments || "{}" });
        }
        if (calls.length === 0) return null;
        message.functionName = calls[0].name;
        message.toolCalls = wire;
        return calls;
    }

    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.endpoint;
    }

    // A tool result is its own message keyed by the id of the call it answers, and the
    // assistant turn that asked carries the calls themselves. A chat saved before this
    // existed has neither field; those messages go out unchanged, as plain prose, and a
    // role of "tool" with no id to match would be rejected, so it degrades to "user".
    function wireMessage(message) {
        if (message.toolCallId && message.toolCallId.length > 0) {
            return {
                "role": "tool",
                "tool_call_id": message.toolCallId,
                "content": message.functionResponse ?? ""
            };
        }
        const calls = message.toolCalls ?? [];
        if (calls.length > 0) {
            return {
                "role": "assistant",
                "content": message.rawContent ?? "",
                "tool_calls": calls.map(c => ({
                    "id": c.id,
                    "type": "function",
                    "function": { "name": c.name, "arguments": c.arguments ?? "{}" }
                }))
            };
        }
        if (message.role === "tool") {
            const legacy = (message.functionResponse ?? "").length > 0 ? message.functionResponse : message.rawContent;
            return { "role": "user", "content": legacy };
        }
        return { "role": message.role, "content": message.rawContent };
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...messages.map(message => wireMessage(message)),
            ],
            "stream": true,
            // Without this a streamed reply carries no usage object at all, so
            // tokenCount stays at -1 and compaction can never fire at any threshold.
            // LiteRT-LM honours it: the chunk before [DONE] comes back with an empty
            // choices array and real counts.
            "stream_options": { "include_usage": true },
            "temperature": temperature,
        };
        if (tools && tools.length > 0) baseData.tools = tools;
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string, model: AiModel): string {
        if (!model?.requires_key) return "";
        // bash's ${VAR:+word}: the whole header is dropped when the key is empty, so
        // no request can carry "Authorization: Bearer " with nothing after it
        return `\$\{${apiKeyEnvVarName}:+-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"\}`;
    }

    function parseResponseLine(line, message) {
        // Remove 'data: ' prefix if present and trim whitespace
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }

        // console.log("[AI] OpenAI: Data:", cleanData);
        
        // Handle special cases
        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
            if (toolCallEmitted) return {};
            // Some providers skip the finish_reason chunk; emit any pending call here
            const fc = takeCompletedToolCalls(message);
            if (fc) return { functionCall: fc[0], functionCalls: fc, finished: true };
            return { finished: true };
        }
        
        // Real stuff
        try {
            const dataJson = JSON.parse(cleanData);

            // Error response handling
            if (dataJson.error) {
                const errorMsg = `**Error**: ${dataJson.error.message || JSON.stringify(dataJson.error)}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            let newContent = "";

            const responseContent = dataJson.choices[0]?.delta?.content || dataJson.message?.content;
            const responseReasoning = dataJson.choices[0]?.delta?.reasoning || dataJson.choices[0]?.delta?.reasoning_content;

            if (responseContent && responseContent.length > 0) {
                if (isReasoning) {
                    isReasoning = false;
                    const endBlock = "\n\n</think>\n\n";
                    message.content += endBlock;
                    message.rawContent += endBlock;
                }
                newContent = responseContent;
            } else if (responseReasoning && responseReasoning.length > 0) {
                if (!isReasoning) {
                    isReasoning = true;
                    const startBlock = "\n\n<think>\n\n";
                    message.rawContent += startBlock;
                    message.content += startBlock;
                }
                newContent = responseReasoning;
            }

            message.content += newContent;
            message.rawContent += newContent;

            // Accumulate streamed tool call fragments
            const toolCallDeltas = dataJson.choices[0]?.delta?.tool_calls;
            if (toolCallDeltas) {
                for (const tc of toolCallDeltas) {
                    let idx = tc.index ?? 0;
                    // LiteRT-LM stamps every call in a turn with index 0 and the same
                    // id, so a name landing on a bucket that has one is a second call,
                    // not a continuation. Without this they concatenate.
                    if (tc.function?.name && pendingToolCalls[idx]?.name)
                        idx = Object.keys(pendingToolCalls).length;
                    if (!pendingToolCalls[idx]) pendingToolCalls[idx] = { name: "", arguments: "", id: "" };
                    if (tc.function?.name) pendingToolCalls[idx].name += tc.function.name;
                    if (tc.function?.arguments) pendingToolCalls[idx].arguments += tc.function.arguments;
                    if (tc.id && pendingToolCalls[idx].id.length === 0) pendingToolCalls[idx].id = tc.id;
                }
            }

            if (dataJson.choices[0]?.finish_reason === "tool_calls") {
                const fc = takeCompletedToolCalls(message);
                if (fc) return { functionCall: fc[0], functionCalls: fc, finished: true };
            }

            // Usage metadata
            if (dataJson.usage) {
                return {
                    tokenUsage: {
                        input: dataJson.usage.prompt_tokens ?? -1,
                        output: dataJson.usage.completion_tokens ?? -1,
                        total: dataJson.usage.total_tokens ?? -1
                    }
                };
            }

            if (dataJson.done) {
                return { finished: true };
            }
            
        } catch (e) {
            console.log("[AI] OpenAI: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }
        
        return {};
    }
    
    function onRequestFinished(message) {
        // OpenAI format doesn't need special finish handling
        return {};
    }
    
    function reset() {
        isReasoning = false;
        pendingToolCalls = ({});
        toolCallEmitted = false;
    }

}
