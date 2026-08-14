; ============================================================================
; DefaultModels.ahk -- AUTO-GENERATED model metadata
;
; Generated from models.dev by scripts\Refresh-Models.ps1 (with corrections
; applied from scripts\models-corrections.json). Do not edit by hand -- use
; Models settings -> Fetch Latest Models or run scripts\Refresh-Models.ps1.
; ============================================================================
models := Map(    ; -- DeepSeek --
    "deepseek/deepseek-chat", {
        provider: "deepseek", api: "openai-completions",
        compat: Map("thinkingFormat", "deepseek", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("high", "high", "max", "max"),
        thinkingOff: "disabled",
        input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1000000, reasoning: false, vision: false
    },
    "deepseek/deepseek-reasoner", {
        provider: "deepseek", api: "openai-completions",
        compat: Map("thinkingFormat", "deepseek", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("high", "high", "max", "max"),
        thinkingOff: "disabled",
        input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1000000, reasoning: true, vision: false
    },
    "deepseek/deepseek-v4-flash", {
        provider: "deepseek", api: "openai-completions",
        compat: Map("thinkingFormat", "deepseek", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "high", "high", "max", "max"),
        thinkingOff: "disabled",
        input: 0.14, cachedInput: 0.0028, output: 0.28, context: 1000000, reasoning: true, vision: false
    },
    "deepseek/deepseek-v4-pro", {
        provider: "deepseek", api: "openai-completions",
        compat: Map("thinkingFormat", "deepseek", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("none", "none", "high", "high", "max", "max"),
        thinkingOff: "disabled",
        input: 0.435, cachedInput: 0.003625, output: 0.87, context: 1000000, reasoning: true, vision: false
    },
    ; -- OpenAI --
    "openai/gpt-4", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 30, cachedInput: 0, output: 60, context: 8192, reasoning: false, vision: false
    },
    "openai/gpt-4.1", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 2, cachedInput: 0.5, output: 8, context: 1047576, reasoning: false, vision: true
    },
    "openai/gpt-4.1-mini", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 0.4, cachedInput: 0.1, output: 1.6, context: 1047576, reasoning: false, vision: true
    },
    "openai/gpt-4.1-nano", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 0.1, cachedInput: 0.025, output: 0.4, context: 1047576, reasoning: false, vision: true
    },
    "openai/gpt-4o", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 2.5, cachedInput: 1.25, output: 10, context: 128000, reasoning: false, vision: true
    },
    "openai/gpt-4o-2024-05-13", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 5, cachedInput: 0, output: 15, context: 128000, reasoning: false, vision: true
    },
    "openai/gpt-4o-2024-08-06", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 2.5, cachedInput: 1.25, output: 10, context: 128000, reasoning: false, vision: true
    },
    "openai/gpt-4o-2024-11-20", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 2.5, cachedInput: 1.25, output: 10, context: 128000, reasoning: false, vision: true
    },
    "openai/gpt-4o-mini", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 0.15, cachedInput: 0.075, output: 0.6, context: 128000, reasoning: false, vision: true
    },
    "openai/gpt-4-turbo", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 10, cachedInput: 0, output: 30, context: 128000, reasoning: false, vision: true
    },
    "openai/gpt-5", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("minimal", "minimal", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "minimal",
        input: 1.25, cachedInput: 0.125, output: 10, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-5.1", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 1.25, cachedInput: 0.125, output: 10, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-5.2", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "none",
        input: 1.75, cachedInput: 0.175, output: 14, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-5.2-chat-latest", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("medium", "medium"),
        thinkingOff: "m",
        input: 1.75, cachedInput: 0.175, output: 14, context: 128000, reasoning: true, vision: true
    },
    "openai/gpt-5.2-pro", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "medium",
        input: 21, cachedInput: 0, output: 168, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-5.3-chat-latest", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "none",
        input: 1.75, cachedInput: 0.175, output: 14, context: 128000, reasoning: false, vision: true
    },
    "openai/gpt-5.3-codex", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "none",
        input: 1.75, cachedInput: 0.175, output: 14, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-5.3-codex-spark", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "none",
        input: 1.75, cachedInput: 0.175, output: 14, context: 128000, reasoning: true, vision: true
    },
    "openai/gpt-5.4", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "none",
        input: 2.5, cachedInput: 0.25, output: 15, context: 1050000, reasoning: true, vision: true
    },
    "openai/gpt-5.4-mini", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "none",
        input: 0.75, cachedInput: 0.075, output: 4.5, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-5.4-nano", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "none",
        input: 0.2, cachedInput: 0.02, output: 1.25, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-5.4-pro", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "medium",
        input: 30, cachedInput: 0, output: 180, context: 1050000, reasoning: true, vision: true
    },
    "openai/gpt-5.5", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "none",
        input: 5, cachedInput: 0.5, output: 30, context: 1050000, reasoning: true, vision: true
    },
    "openai/gpt-5.5-pro", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "medium",
        input: 30, cachedInput: 0, output: 180, context: 1050000, reasoning: true, vision: true
    },
    "openai/gpt-5.6", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
        thinkingOff: "none",
        input: 5, cachedInput: 0.5, output: 30, context: 1050000, reasoning: true, vision: true
    },
    "openai/gpt-5.6-luna", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
        thinkingOff: "none",
        input: 0.2, cachedInput: 0.02, output: 1.2, context: 1050000, reasoning: true, vision: true
    },
    "openai/gpt-5.6-sol", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
        thinkingOff: "none",
        input: 5, cachedInput: 0.5, output: 30, context: 1050000, reasoning: true, vision: true
    },
    "openai/gpt-5.6-terra", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("none", "none", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh", "max", "max"),
        thinkingOff: "none",
        input: 2, cachedInput: 0.2, output: 12, context: 1050000, reasoning: true, vision: true
    },
    "openai/gpt-5-mini", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("minimal", "minimal", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "minimal",
        input: 0.25, cachedInput: 0.025, output: 2, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-5-nano", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("minimal", "minimal", "low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "minimal",
        input: 0.05, cachedInput: 0.005, output: 0.4, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-5-pro", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("high", "high"),
        thinkingOff: "h",
        input: 15, cachedInput: 0, output: 120, context: 400000, reasoning: true, vision: true
    },
    "openai/gpt-realtime-2.1", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("minimal", "minimal", "low", "low", "medium", "medium", "high", "high", "xhigh", "xhigh"),
        thinkingOff: "minimal",
        input: 4, cachedInput: 0.4, output: 24, context: 128000, reasoning: true, vision: true
    },
    "openai/o1", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "low",
        input: 15, cachedInput: 7.5, output: 60, context: 200000, reasoning: true, vision: true
    },
    "openai/o1-pro", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "low",
        input: 150, cachedInput: 0, output: 600, context: 200000, reasoning: true, vision: true
    },
    "openai/o3", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "low",
        input: 2, cachedInput: 0.5, output: 8, context: 200000, reasoning: true, vision: true
    },
    "openai/o3-mini", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "low",
        input: 1.1, cachedInput: 0.55, output: 4.4, context: 200000, reasoning: true, vision: false
    },
    "openai/o3-pro", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "low",
        input: 20, cachedInput: 0, output: 80, context: 200000, reasoning: true, vision: true
    },
    "openai/o4-mini", {
        provider: "openai", api: "openai-completions",
        compat: Map("thinkingFormat", "openai", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_completion_tokens"),
        thinkingLevelMap: Map("low", "low", "medium", "medium", "high", "high"),
        thinkingOff: "low",
        input: 1.1, cachedInput: 0.275, output: 4.4, context: 200000, reasoning: true, vision: true
    },
    ; -- Google Gemini --
    "google/deep-research-max-preview-04-2026", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 2, cachedInput: 0.2, output: 12, context: 131072, reasoning: true, vision: true
    },
    "google/deep-research-preview-04-2026", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 2, cachedInput: 0.2, output: 12, context: 131072, reasoning: true, vision: true
    },
    "google/gemini-2.5-computer-use-preview-10-2025", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 1.25, cachedInput: 0, output: 10, context: 131072, reasoning: true, vision: true
    },
    "google/gemini-2.5-flash", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 0.3, cachedInput: 0.03, output: 2.5, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-2.5-flash-lite", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 0.1, cachedInput: 0.01, output: 0.4, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-2.5-pro", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 1.25, cachedInput: 0.125, output: 10, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3.1-flash-lite", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 0.25, cachedInput: 0.025, output: 1.5, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3.1-flash-lite-image", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 0.25, cachedInput: 0, output: 30, context: 65536, reasoning: true, vision: true
    },
    "google/gemini-3.1-flash-lite-preview", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 0.25, cachedInput: 0.025, output: 1.5, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3.1-flash-live-preview", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 0.75, cachedInput: 0, output: 4.5, context: 131072, reasoning: true, vision: true
    },
    "google/gemini-3.1-pro-preview", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 2, cachedInput: 0.2, output: 12, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3.1-pro-preview-customtools", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 2, cachedInput: 0.2, output: 12, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3.5-flash", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 1.5, cachedInput: 0.15, output: 9, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3.5-flash-lite", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 0.3, cachedInput: 0.03, output: 2.5, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3.6-flash", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 1.5, cachedInput: 0.15, output: 7.5, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3.7-flash", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 0.75, cachedInput: 0.075, output: 3.75, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-3-flash-preview", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 0.5, cachedInput: 0.05, output: 3, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-flash-latest", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 1.5, cachedInput: 0.15, output: 9, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-flash-lite-latest", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("minimal", "MINIMAL", "low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "MINIMAL",
        input: 0.25, cachedInput: 0.025, output: 1.5, context: 1048576, reasoning: true, vision: true
    },
    "google/gemini-robotics-er-1.6-preview", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 1, cachedInput: 0, output: 5, context: 131072, reasoning: true, vision: true
    },
    "google/gemma-4-26b-a4b-it", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 0, cachedInput: 0, output: 0, context: 262144, reasoning: true, vision: true
    },
    "google/gemma-4-31b-it", {
        provider: "google", api: "openai-completions",
        compat: Map("thinkingFormat", "google", "supportsReasoningEffort", true, "supportsUsageInStreaming", true, "maxTokensField", "max_tokens"),
        thinkingLevelMap: Map("low", "LOW", "medium", "MEDIUM", "high", "HIGH"),
        thinkingOff: "LOW",
        input: 0, cachedInput: 0, output: 0, context: 262144, reasoning: true, vision: true
    },
)