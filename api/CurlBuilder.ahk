; ----------------------------------------------------
; CurlBuilder.ahk — cURL command construction
;
; Builds cURL commands for OpenAI-compatible chat completions APIs.
; All providers (DeepSeek, OpenAI, Google) use the standard
; /v1/chat/completions endpoint with JSON request bodies.
;
; NOT suitable for providers with non-OpenAI-compatible APIs
; (e.g. native Anthropic Messages, Gemini GenAI SDK).
;
; Extracted from LLMRequestBuilder.ahk to separate HTTP transport
; from business logic (request building, response parsing).
; ----------------------------------------------------

class CurlBuilder {

    ; Build the cURL command for a non-streaming request.
    ; providerInfo from LLMRequestBuilder.ResolveProvider().
    static Build(providerInfo, requestFile, outputFile) {
        ; A provider with no endpoint would produce a malformed
        ; URL-less cURL command - return "" so callers surface a friendly
        ; "No endpoint configured" error instead of raw cURL stderr.
        if !providerInfo.endpoint
            return ""
        CurlBuilder._LogBuild("chat", providerInfo, providerInfo.endpoint, requestFile, outputFile)
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . providerInfo.endpoint ' '
            . '-H "Authorization: Bearer ' CurlBuilder._SafeApiKey(providerInfo.apiKey) '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '"'
    }

    ; Build the streaming cURL command.
    ; errorFile = path to capture stderr (e.g., cURLError_*.txt)
    static BuildStream(providerInfo, requestFile, outputFile, errorFile) {
        ; Apply the same empty-endpoint guard as Build.
        if !providerInfo.endpoint
            return ""
        ; Streaming commands need an overall --max-time so
        ; a stalled upstream that accepts the connection and then sends
        ; nothing would otherwise hang the chat UI forever (the non-streaming
        ; Build already had one).
        CurlBuilder._LogBuild("stream", providerInfo, providerInfo.endpoint, requestFile, outputFile)
        return 'cURL.exe -s --no-buffer --connect-timeout 30 --max-time 120 -X POST '
            . providerInfo.endpoint ' '
            . '-H "Authorization: Bearer ' CurlBuilder._SafeApiKey(providerInfo.apiKey) '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '" '
            . '2>"' errorFile '"'
    }

    ; Build the FIM cURL command. FIM payloads are completion-style and must
    ; never be sent to a provider's normal chat endpoint.
    static BuildFIM(providerInfo, requestFile, outputFile) {
        endpoint := providerInfo.fimEndpoint
        ; An empty FIM endpoint means this provider does not support AhkLLM's
        ; FIM workflow. Callers surface that capability failure to the user.
        if !endpoint
            return ""
        CurlBuilder._LogBuild("fim", providerInfo, endpoint, requestFile, outputFile)
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . endpoint ' '
            . '-H "Authorization: Bearer ' CurlBuilder._SafeApiKey(providerInfo.apiKey) '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '"'
    }

    ; Log transport selection without exposing the bearer token or command.
    static _LogBuild(mode, providerInfo, endpoint, requestFile, outputFile) {
        safeAuthLength := StrLen(CurlBuilder._SafeApiKey(providerInfo.apiKey))
        debugLog("mode=" mode " provider=" (providerInfo.HasOwnProp("providerKey") ? providerInfo.providerKey : "")
            . " model=" (providerInfo.HasOwnProp("modelName") ? providerInfo.modelName : "")
            . " endpoint=" endpoint
            . " authPresent=" (providerInfo.apiKey != "" ? "true" : "false")
            . " authLength=" StrLen(providerInfo.apiKey)
            . " safeAuthLength=" safeAuthLength
            . " requestFile=" requestFile " outputFile=" outputFile, "CurlBuilder")
    }

    ; Security: the API key is embedded in a quoted header on
    ; the cURL command line - remove characters that can break the quote or
    ; inject commands when the command runs through cmd. Bearer tokens never
    ; legitimately contain these.
    static _SafeApiKey(key) {
        key := StrReplace(key, '"', '')
        key := StrReplace(key, '%', '')
        key := StrReplace(key, '&', '')
        key := StrReplace(key, '|', '')
        key := StrReplace(key, '<', '')
        key := StrReplace(key, '>', '')
        key := StrReplace(key, '^', '')
        return key
    }

}
