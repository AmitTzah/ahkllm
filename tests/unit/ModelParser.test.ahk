; ======================================================
; ModelParser.test.ahk — Unit tests for ModelParser.ahk
; ======================================================

class ModelParserTest {

    static __New() {
        RegisterTestClass("ModelParserTest")
    }

    ; ----------------------------------------------------
    ; StripProvider
    ; ----------------------------------------------------
    StripProvider_RemovesProviderPrefix() {
        result := ModelParser.StripProvider("openai/gpt-4o")
        if result != "gpt-4o"
            throw Error("Expected 'gpt-4o', got '" result "'")
    }

    StripProvider_NoProvider_ReturnsSame() {
        result := ModelParser.StripProvider("gpt-4o")
        if result != "gpt-4o"
            throw Error("Expected 'gpt-4o', got '" result "'")
    }

    StripProvider_MultipleSlashes_StripsFirstOnly() {
        result := ModelParser.StripProvider("openai/gpt-4o/variant")
        if result != "gpt-4o/variant"
            throw Error("Expected 'gpt-4o/variant', got '" result "'")
    }

    StripProvider_EmptyString_ReturnsEmpty() {
        result := ModelParser.StripProvider("")
        if result != ""
            throw Error("Expected empty string, got '" result "'")
    }

    CanonicalProvider_PreservesIndependentCodex() {
        if ModelParser.CanonicalProvider("codex") != "codex"
            throw Error("Codex provider must remain independent")
        if ModelParser.CanonicalProvider("openai") != "openai"
            throw Error("Unrelated providers must not be rewritten")
    }

    Canonicalize_PreservesCodexModelId() {
        if ModelParser.Canonicalize("codex/gpt-5.6-luna") != "codex/gpt-5.6-luna"
            throw Error("Codex model id must retain its provider")
        if ModelParser.Canonicalize("chatgpt/gpt-5.6-luna") != "chatgpt/gpt-5.6-luna"
            throw Error("Canonical ChatGPT-plan id must remain unchanged")
    }

    IsChatGptPlan_ExcludesCodexCli() {
        if !ModelParser.IsChatGptPlan("chatgpt/gpt-5.6-luna")
            throw Error("Canonical chatgpt id should be recognized as ChatGPT plan")
        if ModelParser.IsChatGptPlan("codex/gpt-5.6-luna")
            throw Error("Codex CLI must not be treated as ChatGPT OAuth")
        if ModelParser.IsChatGptPlan("openai/gpt-5-mini")
            throw Error("OpenAI API-key model must not be treated as ChatGPT plan")
    }

    Lookup_KeepsTransportSpecificMetadataWithinProvider() {
        catalog := Map(
            "chatgpt/gpt-example", { api: "chatgpt-responses" },
            "codex/gpt-example", { api: "codex-cli" }
        )
        if ModelResolver.Lookup(catalog, "codex/gpt-example-2026-10-04").api != "codex-cli"
            throw Error("Version fallback must retain Codex transport metadata")
        if ModelResolver.Lookup(catalog, "chatgpt/gpt-example-2026-10-04").api != "chatgpt-responses"
            throw Error("Version fallback must retain ChatGPT transport metadata")
        if ModelResolver.Lookup(Map("chatgpt/gpt-example", { api: "chatgpt-responses" }), "codex/gpt-example") != ""
            throw Error("Missing Codex metadata must not be borrowed from ChatGPT")
    }

    SupportsImageGeneration_AcceptsBothSubscriptionTransports() {
        if !ModelParser.SupportsImageGeneration("codex/gpt-5.6-luna")
            || !ModelParser.SupportsImageGeneration("chatgpt/gpt-5.6-luna")
            || ModelParser.SupportsImageGeneration("openai/gpt-5-mini")
            throw Error("Only the two subscription transports support the image-generation toggle")
    }

    ; ----------------------------------------------------
    ; StripVersion
    ; ----------------------------------------------------
    StripVersion_RemovesDateSuffix() {
        result := ModelParser.StripVersion("gpt-4.1-2025-04-14")
        if result != "gpt-4.1"
            throw Error("Expected 'gpt-4.1', got '" result "'")
    }

    StripVersion_NoSuffix_ReturnsSame() {
        result := ModelParser.StripVersion("deepseek-v4-flash")
        if result != "deepseek-v4-flash"
            throw Error("Expected 'deepseek-v4-flash', got '" result "'")
    }

    StripVersion_CompactDate() {
        result := ModelParser.StripVersion("claude-3-5-sonnet-20241022")
        if result != "claude-3-5-sonnet"
            throw Error("Expected 'claude-3-5-sonnet', got '" result "'")
    }

}
