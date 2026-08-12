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
        ; Bug #112: a provider with no endpoint would produce a malformed
        ; URL-less cURL command - return "" so callers surface a friendly
        ; "No endpoint configured" error instead of raw cURL stderr.
        if !providerInfo.endpoint
            return ""
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
        ; Bug #112: same empty-endpoint guard as Build.
        if !providerInfo.endpoint
            return ""
        ; Bug #204: the streaming command MUST have an overall --max-time -
        ; a stalled upstream that accepts the connection and then sends
        ; nothing would otherwise hang the chat UI forever (the non-streaming
        ; Build already had one).
        return 'cURL.exe -s --no-buffer --connect-timeout 30 --max-time 120 -X POST '
            . providerInfo.endpoint ' '
            . '-H "Authorization: Bearer ' CurlBuilder._SafeApiKey(providerInfo.apiKey) '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '" '
            . '2>"' errorFile '"'
    }

    ; Build the FIM cURL command (uses FIM endpoint, falls back to chat endpoint).
    static BuildFIM(providerInfo, requestFile, outputFile) {
        endpoint := providerInfo.fimEndpoint
        if !endpoint {
            endpoint := providerInfo.endpoint
        }
        ; Bug #112: same empty-endpoint guard as Build.
        if !endpoint
            return ""
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . endpoint ' '
            . '-H "Authorization: Bearer ' CurlBuilder._SafeApiKey(providerInfo.apiKey) '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '"'
    }

    ; Bug #89 (security): the API key is embedded in a "..."-quoted header on
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
