import QtQuick

ApiStrategy {
    property bool isReasoning: false
    
    function buildEndpoint(model: AiModel): string {
        // console.log("[AI] Endpoint: " + model.endpoint);
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: systemPrompt},
                ...messages.map(message => wireMessage(message)),
            ],
            "stream": true,
            "temperature": temperature,
        };
        if (tools && tools.length > 0) baseData.tools = tools;
        // console.log("[AI] Request data: ", JSON.stringify(baseData, null, 2));
        return model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;
    }

    // Same protocol as OpenAI: the call rides on the assistant turn, the result is
    // its own message keyed by the id of the call it answers.
    function wireMessage(message) {
        if (message.toolCallId && message.toolCallId.length > 0) {
            return {
                "role": "tool",
                "name": message.functionName,
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
        // saved before the protocol landed: no id to match, so it cannot be a tool turn
        if (message.role === "tool") {
            const legacy = (message.functionResponse ?? "").length > 0 ? message.functionResponse : message.rawContent;
            return { "role": "user", "content": legacy };
        }
        return { "role": message.role, "content": message.rawContent };
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string, model: AiModel): string {
        if (!model?.requires_key) return "";
        return `-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"`;
    }

    function parseResponseLine(line, message) {
        // Remove 'data: ' prefix if present and trim whitespace
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }
        
        // Handle special cases
        if (!cleanData || cleanData.startsWith(":")) return {};
        if (cleanData === "[DONE]") {
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

            // Function calls
            if (dataJson.choices[0]?.delta?.tool_calls) {
                const calls = [];
                const wire = [];
                for (let k = 0; k < dataJson.choices[0].delta.tool_calls.length; k++) {
                    const tc = dataJson.choices[0].delta.tool_calls[k];
                    let functionArgs = {};
                    try { functionArgs = JSON.parse(tc.function.arguments) || {}; } // Args are given as string???
                    catch (e) { console.log("[AI] Mistral: Could not parse tool call arguments: ", e); }
                    const id = tc.id ?? `call_${k}`;
                    calls.push({ name: tc.function.name, args: functionArgs, id: id });
                    wire.push({ "id": id, "name": tc.function.name, "arguments": tc.function.arguments ?? "{}" });
                }
                if (calls.length > 0) {
                    message.functionName = calls[0].name;
                    message.functionCall = calls[0];
                    message.toolCalls = wire;
                    return { functionCall: calls[0], functionCalls: calls };
                }
            }

            // Thinking?
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

            // Text
            message.content += newContent;
            message.rawContent += newContent;

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

            if (`dataJson`.done) {
                return { finished: true };
            }
            
        } catch (e) {
            console.log("[AI] Mistral: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }
        
        return {};
    }
    
    function onRequestFinished(message) {
        return {};
    }
    
    function reset() {
        isReasoning = false;
    }

}
