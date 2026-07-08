; ----------------------------------------------------
; CurlBuilder.ahk — cURL command construction
;
; Extracted from LLMRequestBuilder.ahk to separate HTTP transport
; from business logic (request building, response parsing).
; ----------------------------------------------------

class CurlBuilder {

    ; Build the cURL command for a non-streaming request.
    ; providerInfo from LLMRequestBuilder.ResolveProvider().
    static Build(providerInfo, requestFile, outputFile) {
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . providerInfo.endpoint ' '
            . '-H "Authorization: Bearer ' providerInfo.apiKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '"'
    }

    ; Build the streaming cURL command.
    ; errorFile = path to capture stderr (e.g., cURLError_*.txt)
    static BuildStream(providerInfo, requestFile, outputFile, errorFile) {
        return 'cURL.exe -s --no-buffer --connect-timeout 30 -X POST '
            . providerInfo.endpoint ' '
            . '-H "Authorization: Bearer ' providerInfo.apiKey '" '
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
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . endpoint ' '
            . '-H "Authorization: Bearer ' providerInfo.apiKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' requestFile '" '
            . '-o "' outputFile '"'
    }

    ; ----------------------------------------------------
    ; Backward Compatible Instance Methods
    ; ----------------------------------------------------
    ; These use global APIEndpoint/FIMEndpoint and an API key
    ; provided at construction time. Used by legacy code and tests.

    __New(APIKey) {
        this.APIKey := APIKey
    }

    buildcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile) {
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . APIEndpoint ' '
            . '-H "Authorization: Bearer ' this.APIKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' chatHistoryJSONRequestFile '" '
            . '-o "' cURLOutputFile '"'
    }

    buildFIMcURLCommand(chatHistoryJSONRequestFile, cURLOutputFile) {
        return 'cURL.exe -s --max-time 120 --connect-timeout 30 -X POST '
            . FIMEndpoint ' '
            . '-H "Authorization: Bearer ' this.APIKey '" '
            . '-H "Content-Type: application/json" '
            . '-d @"' chatHistoryJSONRequestFile '" '
            . '-o "' cURLOutputFile '"'
    }
}
