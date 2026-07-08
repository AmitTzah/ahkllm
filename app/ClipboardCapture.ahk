; ----------------------------------------------------
; ClipboardCapture — Text capture via clipboard
;
; Handles both FIM and non-FIM clipboard capture.
; Extracted from RequestProcessor.ahk.
; ----------------------------------------------------

class ClipboardCapture {

    ; Returns { success, userMessage?, prefix?, suffix?, modelsStr }
    static Capture(isFIM, pasteMode, customInputMessage) {
        clipboardBeforeCopy := A_Clipboard

        if isFIM
            return ClipboardCapture._CaptureFIM(clipboardBeforeCopy, pasteMode)
        else
            return ClipboardCapture._CaptureChat(clipboardBeforeCopy, customInputMessage)
    }

    static _CaptureFIM(clipboardBeforeCopy, pasteMode) {
        prefix := ""
        suffix := ""

        A_Clipboard := ""
        Send("^c")

        selection := ""
        if !ClipWait(1) {
            A_Clipboard := ""
            Send("^+{Home}^c")
            if !ClipWait(1) {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "No text found before cursor." }
            }
            prefix := A_Clipboard
            suffix := ""
        } else {
            selection := A_Clipboard

            if pasteMode = "replace" {
                A_Clipboard := ""
                Send("^x")
                if !ClipWait(1) {
                    A_Clipboard := clipboardBeforeCopy
                    return { success: false, error: "Could not cut the selected text." }
                }
                A_Clipboard := ""
                Send("^+{Home}^c")
                if !ClipWait(1) {
                    prefix := ""
                } else {
                    prefix := A_Clipboard
                }
                Send("{Right}")
                Sleep 50
                A_Clipboard := ""
                Send("+^{End}^c")
                if !ClipWait(1) {
                    suffix := ""
                } else {
                    suffix := A_Clipboard
                }
                Send("{Left}")
            } else {
                prefix := selection
                suffix := ""
            }
        }

        A_Clipboard := clipboardBeforeCopy
        return { success: true, prefix: prefix, suffix: suffix, modelsStr: "", isFIM: true }
    }

    static _CaptureChat(clipboardBeforeCopy, customInputMessage) {
        A_Clipboard := ""
        Critical("On")
        SendInput("^c")
        copied := ClipWait(0.5)
        if !copied {
            A_Clipboard := ""
            Send("^c")
            copied := ClipWait(1.5)
        }
        if !copied {
            A_Clipboard := ""
            Send("^{Insert}")
            copied := ClipWait(1)
        }
        Critical("Off")

        userMessage := ""
        if !copied {
            if customInputMessage != "" {
                userMessage := customInputMessage
            } else {
                A_Clipboard := clipboardBeforeCopy
                return { success: false, error: "The attempt to copy text onto the clipboard failed." }
            }
        } else if customInputMessage != "" {
            userMessage := customInputMessage "`n`n" A_Clipboard
        } else {
            userMessage := A_Clipboard
        }

        A_Clipboard := clipboardBeforeCopy
        return { success: true, userMessage: userMessage, modelsStr: "", isFIM: false }
    }
}
