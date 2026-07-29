import QtQuick

ApiStrategy {
    property bool isReasoning: false
    // tool_calls stream as fragments (name in the first delta, arguments split
    // across many); accumulate per index and emit once on finish_reason/[DONE]
    property var pendingToolCalls: ({})
    property bool toolCallEmitted: false

    function takeCompletedToolCall(message) {
        const indices = Object.keys(pendingToolCalls);
        if (indices.length === 0 || toolCallEmitted) return null;
        toolCallEmitted = true;
        const call = pendingToolCalls[indices[0]];
        let args = {};
        try {
            if (call.arguments && call.arguments.length > 0) args = JSON.parse(call.arguments);
        } catch (e) {
            console.log("[AI] OpenAI: Could not parse tool call arguments: ", e);
        }
        message.functionName = call.name;
        const newContent = `\n\n[[ Function: ${call.name}(${call.arguments || "{}"}) ]]\n`;
        message.rawContent += newContent;
        message.content += newContent;
        return { name: call.name, args: args };
    }

    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...messages.map(message => {
                    return {
                        "role": message.role,
                        "content": message.rawContent,
                    }
                }),
            ],
            "stream": true,
            "tools": tools,
            "temperature": temperature,
        };
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
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
            const fc = takeCompletedToolCall(message);
            if (fc) return { functionCall: fc, finished: true };
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
                    const idx = tc.index ?? 0;
                    if (!pendingToolCalls[idx]) pendingToolCalls[idx] = { name: "", arguments: "" };
                    if (tc.function?.name) pendingToolCalls[idx].name += tc.function.name;
                    if (tc.function?.arguments) pendingToolCalls[idx].arguments += tc.function.arguments;
                }
            }

            if (dataJson.choices[0]?.finish_reason === "tool_calls") {
                const fc = takeCompletedToolCall(message);
                if (fc) return { functionCall: fc, finished: true };
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
