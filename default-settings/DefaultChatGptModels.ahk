; Curated ChatGPT OAuth fallback models; account discovery replaces only these entries.

models["chatgpt/gpt-5.6-luna"] := {
    provider: "chatgpt", api: "chatgpt-responses",
    compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", ""),
    thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
    thinkingOff: "none",
    input: 0, cachedInput: 0, output: 0, context: 0, reasoning: true, vision: true
}

models["chatgpt/gpt-5.6-terra"] := {
    provider: "chatgpt", api: "chatgpt-responses",
    compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", ""),
    thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
    thinkingOff: "none",
    input: 0, cachedInput: 0, output: 0, context: 0, reasoning: true, vision: true
}

models["chatgpt/gpt-5.6-sol"] := {
    provider: "chatgpt", api: "chatgpt-responses",
    compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", ""),
    thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
    thinkingOff: "none",
    input: 0, cachedInput: 0, output: 0, context: 0, reasoning: true, vision: true
}

models["chatgpt/gpt-6-astra"] := {
    provider: "chatgpt", api: "chatgpt-responses",
    compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", ""),
    thinkingLevelMap: Map("low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
    thinkingOff: "low",
    input: 0, cachedInput: 0, output: 0, context: 0, reasoning: true, vision: true
}
