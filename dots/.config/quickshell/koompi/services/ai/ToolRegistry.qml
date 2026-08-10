import qs.modules.common
import QtQuick

/**
 * One declaration per tool, rendered per wire format.
 *
 * An entry is `name`, `description`, `parameters`, `formats`, `enabled`, plus
 * `risk` (safe | reads-system | writes-system | leaves-machine) and `approval`
 * (never | once | always). `risk` is what the approval surface renders;
 * `approval` is what ToolRunner asks before running. The handler lives next to
 * the processes it drives, in ToolRunner.handlers, keyed by the same name.
 *
 * Gemini: https://ai.google.dev/gemini-api/docs/function-calling
 * OpenAI: https://platform.openai.com/docs/guides/function-calling
 */
QtObject {
    id: root

    // The model's own eyes on the web. Without these its only lookup is `recall`,
    // which searches this user's memory rather than the world, so it answers "I have
    // no information" to anything outside its training data. Search goes through the
    // local SearXNG; the answer is still written by whichever model is loaded here.
    readonly property bool webToolsEnabled: Config.options?.ai?.webSearch ?? true

    // A capable agent with a shell, this filesystem and the web, one call deep. The
    // local model cannot read the machine it runs on and will answer hardware
    // questions from training data instead, so anything about *this* box goes here.
    readonly property bool agentToolEnabled: Config.options?.ai?.agentTool ?? true

    readonly property var emptyParameters: ({ "type": "object", "properties": {} })

    readonly property var entries: [
        {
            "name": "switch_to_search_mode",
            "risk": "leaves-machine",
            "approval": "never",
            "description": "Search the web",
            "formats": ["gemini"],
            "enabled": true
        },
        {
            "name": "get_shell_config",
            "risk": "reads-system",
            "approval": "never",
            "description": "Get the desktop shell config file contents",
            "parameters": root.emptyParameters,
            "formats": ["gemini", "openai", "mistral"],
            "enabled": true
        },
        {
            "name": "set_shell_config",
            "risk": "writes-system",
            "approval": "never",
            "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
            "parameters": {
                "type": "object",
                "properties": {
                    "key": {
                        "type": "string",
                        "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                    },
                    "value": {
                        "type": "string",
                        "description": "The value to set, e.g. `true`"
                    }
                },
                "required": ["key", "value"]
            },
            "formats": ["gemini", "openai", "mistral"],
            "enabled": true
        },
        {
            "name": "run_shell_command",
            "risk": "writes-system",
            "approval": "once",
            "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The bash command to run",
                    },
                },
                "required": ["command"]
            },
            "formats": ["gemini", "openai", "mistral"],
            "enabled": true
        },
        {
            "name": "set_owner_name",
            "risk": "writes-system",
            "approval": "never",
            "description": "Remember the name the user wants to be called. Call this as soon as the user tells you their name, so you can address them properly in this and future conversations.",
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "The name the user wants to be called, e.g. `Alice`",
                    },
                },
                "required": ["name"]
            },
            "formats": ["gemini", "openai", "mistral"],
            "enabled": true
        },
        {
            "name": "remember",
            "risk": "writes-system",
            "approval": "never",
            "description": "Store a durable fact in long-term memory for future conversations. Use for preferences, important personal facts, and ongoing projects — not trivial chatter.",
            "parameters": {
                "type": "object",
                "properties": {
                    "text": {
                        "type": "string",
                        "description": "The fact to remember, as a self-contained sentence, e.g. `The user prefers dark mode`",
                    },
                    "type": {
                        "type": "string",
                        "description": "One of: profile, preference, fact, task",
                    },
                },
                "required": ["text"]
            },
            "formats": ["gemini", "openai", "mistral"],
            "enabled": true
        },
        {
            "name": "recall",
            "risk": "reads-system",
            "approval": "never",
            "description": "Search long-term memory for facts relevant to a query. Use when you need to remember something about the user that isn't already in the context.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "What to look up, e.g. `user's editor preferences`",
                    },
                },
                "required": ["query"]
            },
            "formats": ["gemini", "openai", "mistral"],
            "enabled": true
        },
        {
            "name": "search_web",
            "risk": "leaves-machine",
            "approval": "never",
            "description": "Search the web and read the top result. Use this for anything you are not certain of: a company, a person, a product, a price, news, documentation, an unfamiliar error. Prefer this over telling the user you have no information.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "What to search for, e.g. `KOOMPI Ministation price`",
                    }
                },
                "required": ["query"]
            },
            "formats": ["gemini", "openai", "mistral"],
            "enabled": root.webToolsEnabled
        },
        {
            "name": "fetch_url",
            "risk": "leaves-machine",
            "approval": "never",
            "description": "Read the text of one web page. Use this when the user names a website or gives a link, and to follow up on a URL that search returned.",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {
                        "type": "string",
                        "description": "The page to read, e.g. `saladigital.org` or `https://koompi.com/about`",
                    }
                },
                "required": ["url"]
            },
            "formats": ["gemini", "openai", "mistral"],
            "enabled": root.webToolsEnabled
        },
        {
            "name": "ask_agent",
            "risk": "leaves-machine",
            "approval": "once",
            "description": "Delegate a task to a capable agent that can run commands on this computer and search the internet. Use it for anything about THIS machine - hardware, laptop model, CPU, RAM, GPU, disk, battery health, drivers, installed packages, running services, logs, why something is broken - and for research that needs several steps. It is slower than the other tools, so send one complete task and answer from what it returns.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task": {
                        "type": "string",
                        "description": "The task, written so the agent needs no other context, e.g. `Inspect this computer and report the laptop model, CPU, RAM, GPU and disk.`",
                    }
                },
                "required": ["task"]
            },
            "formats": ["gemini", "openai", "mistral"],
            "enabled": root.agentToolEnabled
        }
    ]

    function entryFor(name: string): var {
        const found = root.entries.filter(e => e.name === name);
        return found.length > 0 ? found[0] : null;
    }

    function riskOf(name: string): string {
        return root.entryFor(name)?.risk ?? "writes-system";
    }

    // Unknown tools are treated as needing a decision, not as safe.
    function approvalOf(name: string): string {
        return root.entryFor(name)?.approval ?? "once";
    }

    function activeEntries(format) {
        return root.entries.filter(e => e.enabled && e.formats.indexOf(format) !== -1);
    }

    // Gemini omits `parameters` entirely for a tool that takes none; sending an
    // empty schema there is rejected.
    function geminiDeclaration(entry) {
        const declaration = { "name": entry.name, "description": entry.description };
        const properties = entry.parameters?.properties ?? {};
        if (Object.keys(properties).length > 0) declaration.parameters = entry.parameters;
        return declaration;
    }

    function openaiDeclaration(entry) {
        return {
            "type": "function",
            "function": {
                "name": entry.name,
                "description": entry.description,
                "parameters": entry.parameters ?? root.emptyParameters
            }
        };
    }

    function declarationsFor(format) {
        const entries = root.activeEntries(format);
        if (format === "gemini") return entries.map(e => root.geminiDeclaration(e));
        return entries.map(e => root.openaiDeclaration(e));
    }

    readonly property var tools: ({
        "gemini": {
            "functions": [{ "functionDeclarations": root.declarationsFor("gemini") }],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": root.declarationsFor("openai"),
            "search": [],
            "none": [],
        },
        "mistral": {
            "functions": root.declarationsFor("mistral"),
            "search": [],
            "none": [],
        }
    })
}
