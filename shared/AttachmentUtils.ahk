; ======================================================
; AttachmentUtils.ahk — Vision gating, MIME classification,
; filename sanitization, and validation.
; ======================================================

#Include ModelResolver.ahk

class AttachmentUtils {

    ; Check if a model has vision capability.
    ; Returns false if models map missing or vision field absent.
    static HasVision(modelName) {
        if !IsSet(models)
            return false
        ; Single lookup accepting full or short model ids (bug #51: short ids
        ; used to be rejected because the map is keyed by "provider/model").
        m := ModelResolver.Lookup(models, modelName)
        if !IsObject(m) || !m.HasOwnProp("vision")
            return false
        return m.vision = true
    }

    ; Validate attachments against the model's capabilities.
    ; Returns array of error strings (empty = all valid).
    static ValidateAttachments(attachments, modelName) {
        errors := []
        hasVision := AttachmentUtils.HasVision(modelName)
        for att in attachments {
            if !IsObject(att)
                continue
            attType := att.HasOwnProp("type") ? att.type : (att.HasOwnProp("attachment_type") ? att.attachment_type : "")
            if attType = "image" && !hasVision {
                errors.Push("Model '" modelName "' does not support vision. Remove images or switch to a vision-capable model.")
                break  ; Only report once
            }
        }
        return errors
    }

    ; ---- MIME type classification ----

    static IsImageMime(mime) {
        return InStr(mime, "image/") = 1
    }

    static IsPDFMime(mime) {
        return mime = "application/pdf"
    }

    static IsDOCXMime(mime) {
        return mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    }

    ; Map MIME type to attachment_type string.
    static GetAttachmentType(mime) {
        if AttachmentUtils.IsImageMime(mime)
            return "image"
        if AttachmentUtils.IsPDFMime(mime)
            return "pdf"
        if AttachmentUtils.IsDOCXMime(mime)
            return "docx"
        return "text_file"
    }

    ; Check if a filename extension is in the allowed text file list.
    static IsAllowedTextFile(filename) {
        allowedExts := Map(
            "txt", 1, "md", 1, "py", 1, "js", 1, "ahk", 1,
            "json", 1, "xml", 1, "csv", 1, "ini", 1, "cfg", 1,
            "yaml", 1, "yml", 1, "log", 1, "html", 1, "css", 1,
            "sql", 1, "bat", 1, "ps1", 1, "sh", 1, "java", 1,
            "c", 1, "cpp", 1, "h", 1, "rs", 1, "go", 1,
            "ts", 1, "tsx", 1, "jsx", 1, "toml", 1
        )
        SplitPath(filename, , , &ext)
        ext := StrLower(ext)
        return allowedExts.Has(ext)
    }

    ; ---- Filename sanitization ----

    ; Remove path traversal characters and limit filename length.
    static SanitizeFilename(name) {
        ; Strip directory separators and dangerous chars
        result := StrReplace(name, "/", "_")
        result := StrReplace(result, "\", "_")
        result := StrReplace(result, "..", "_")
        result := StrReplace(result, ":", "_")
        result := StrReplace(result, "*", "_")
        result := StrReplace(result, "?", "_")
        result := StrReplace(result, Chr(34), "_")
        result := StrReplace(result, "<", "_")
        result := StrReplace(result, ">", "_")
        result := StrReplace(result, "|", "_")
        ; Limit to 200 chars
        if StrLen(result) > 200
            result := SubStr(result, -199)
        ; If empty after sanitization, use default
        if result = ""
            result := "unnamed_file"
        return result
    }

}
