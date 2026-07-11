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
}
