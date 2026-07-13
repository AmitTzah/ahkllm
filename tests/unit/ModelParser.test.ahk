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
