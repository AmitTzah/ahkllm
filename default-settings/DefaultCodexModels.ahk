; Curated Codex CLI models, independent of the ChatGPT OAuth account catalog.

models["codex/gpt-5.6-luna"] := {
    provider: "codex", api: "codex-cli",
    compat: Map("thinkingFormat", "codex-cli", "supportsReasoningEffort", true, "supportsUsageInStreaming", false, "maxTokensField", ""),
    thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
    thinkingOff: "none",
    input: 0, cachedInput: 0, output: 0, context: 0, reasoning: true, vision: true
}

models["codex/gpt-5.6-terra"] := {
    provider: "codex", api: "codex-cli",
    compat: Map("thinkingFormat", "codex-cli", "supportsReasoningEffort", true, "supportsUsageInStreaming", false, "maxTokensField", ""),
    thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
    thinkingOff: "none",
    input: 0, cachedInput: 0, output: 0, context: 0, reasoning: true, vision: true
}

models["codex/gpt-5.6-sol"] := {
    provider: "codex", api: "codex-cli",
    compat: Map("thinkingFormat", "codex-cli", "supportsReasoningEffort", true, "supportsUsageInStreaming", false, "maxTokensField", ""),
    thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
    thinkingOff: "none",
    input: 0, cachedInput: 0, output: 0, context: 0, reasoning: true, vision: true
}

models["codex/gpt-6-astra"] := {
    provider: "codex", api: "codex-cli",
    compat: Map("thinkingFormat", "codex-cli", "supportsReasoningEffort", true, "supportsUsageInStreaming", false, "maxTokensField", ""),
    thinkingLevelMap: Map("low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
    thinkingOff: "low",
    input: 0, cachedInput: 0, output: 0, context: 0, reasoning: true, vision: true
}
