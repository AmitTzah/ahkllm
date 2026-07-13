; ======================================================
; AttachmentUtils.test.ahk — Unit tests for AttachmentUtils
;
; Tests: vision gating, mime classification, filename
; sanitization, token estimation.
; ======================================================

class AttachmentUtilsTest {

    static __New() {
        RegisterTestClass("AttachmentUtilsTest")
    }

    ; ---- Vision Gating ----

    HasVision_KnownVisionModel_ReturnsTrue() {
        ; google/gemini-2.5-flash has vision:true in test_config
        if !AttachmentUtils.HasVision("google/gemini-2.5-flash")
            throw Error("Expected vision=true for gemini-2.5-flash")
    }

    HasVision_NonVisionModel_ReturnsFalse() {
        ; deepseek-v4-flash has vision:false in test_config
        if AttachmentUtils.HasVision("deepseek/deepseek-v4-flash")
            throw Error("Expected vision=false for deepseek-v4-flash")
    }

    HasVision_UnknownModel_ReturnsFalse() {
        if AttachmentUtils.HasVision("nonexistent/model")
            throw Error("Expected vision=false for unknown model")
    }

    ValidateAttachments_ImageWithVisionModel_ReturnsEmpty() {
        attachments := [{type: "image"}]
        errors := AttachmentUtils.ValidateAttachments(attachments, "google/gemini-2.5-flash")
        if errors.Length != 0
            throw Error("Expected no errors for vision model + image")
    }

    ValidateAttachments_ImageWithNonVisionModel_ReturnsError() {
        attachments := [{type: "image"}]
        errors := AttachmentUtils.ValidateAttachments(attachments, "deepseek/deepseek-v4-flash")
        if errors.Length = 0
            throw Error("Expected error for non-vision model + image")
    }

    ValidateAttachments_TextFileWithNonVisionModel_ReturnsEmpty() {
        attachments := [{type: "text_file"}]
        errors := AttachmentUtils.ValidateAttachments(attachments, "deepseek/deepseek-v4-flash")
        if errors.Length != 0
            throw Error("Expected no errors for non-vision model + text file")
    }

    ; ---- MIME Classification ----

    IsImageMime_PNG_ReturnsTrue() {
        if !AttachmentUtils.IsImageMime("image/png")
            throw Error("Expected image/png to be image mime")
    }

    IsImageMime_JPEG_ReturnsTrue() {
        if !AttachmentUtils.IsImageMime("image/jpeg")
            throw Error("Expected image/jpeg to be image mime")
    }

    IsImageMime_PDF_ReturnsFalse() {
        if AttachmentUtils.IsImageMime("application/pdf")
            throw Error("Expected application/pdf NOT to be image mime")
    }

    IsPDFMime_ReturnsTrue() {
        if !AttachmentUtils.IsPDFMime("application/pdf")
            throw Error("Expected application/pdf to be PDF mime")
    }

    IsDOCXMime_ReturnsTrue() {
        if !AttachmentUtils.IsDOCXMime("application/vnd.openxmlformats-officedocument.wordprocessingml.document")
            throw Error("Expected DOCX mime to be recognized")
    }

    GetAttachmentType_Image() {
        if AttachmentUtils.GetAttachmentType("image/png") != "image"
            throw Error("Expected 'image' for image/png")
    }

    GetAttachmentType_PDF() {
        if AttachmentUtils.GetAttachmentType("application/pdf") != "pdf"
            throw Error("Expected 'pdf' for application/pdf")
    }

    GetAttachmentType_DOCX() {
        if AttachmentUtils.GetAttachmentType("application/vnd.openxmlformats-officedocument.wordprocessingml.document") != "docx"
            throw Error("Expected 'docx' for DOCX mime")
    }

    GetAttachmentType_PlainText() {
        if AttachmentUtils.GetAttachmentType("text/plain") != "text_file"
            throw Error("Expected 'text_file' for text/plain")
    }

    ; ---- Text File Extension Check ----

    IsAllowedTextFile_TXT_ReturnsTrue() {
        if !AttachmentUtils.IsAllowedTextFile("readme.txt")
            throw Error("Expected .txt to be allowed")
    }

    IsAllowedTextFile_PY_ReturnsTrue() {
        if !AttachmentUtils.IsAllowedTextFile("main.py")
            throw Error("Expected .py to be allowed")
    }

    IsAllowedTextFile_AHK_ReturnsTrue() {
        if !AttachmentUtils.IsAllowedTextFile("script.ahk")
            throw Error("Expected .ahk to be allowed")
    }

    IsAllowedTextFile_EXE_ReturnsFalse() {
        if AttachmentUtils.IsAllowedTextFile("virus.exe")
            throw Error("Expected .exe NOT to be allowed")
    }

    IsAllowedTextFile_NoExtension_ReturnsFalse() {
        if AttachmentUtils.IsAllowedTextFile("README")
            throw Error("Expected no-extension file NOT to be allowed")
    }

    ; ---- Filename Sanitization ----

    SanitizeFilename_PathTraversal_RemovesDots() {
        result := AttachmentUtils.SanitizeFilename("..\..\evil.png")
        if InStr(result, "..")
            throw Error("Path traversal '..' should be removed, got: " result)
    }

    SanitizeFilename_Backslash_Replaces() {
        result := AttachmentUtils.SanitizeFilename("path\to\file.txt")
        if InStr(result, "\")
            throw Error("Backslash should be replaced, got: " result)
    }

    SanitizeFilename_Colon_Replaces() {
        result := AttachmentUtils.SanitizeFilename("C:file.txt")
        if InStr(result, ":")
            throw Error("Colon should be replaced, got: " result)
    }

    SanitizeFilename_NormalName_Preserves() {
        result := AttachmentUtils.SanitizeFilename("screenshot_2024.png")
        if result != "screenshot_2024.png"
            throw Error("Normal filename should be preserved, got: " result)
    }

    SanitizeFilename_EmptyString_ReturnsDefault() {
        result := AttachmentUtils.SanitizeFilename("")
        if result = ""
            throw Error("Empty filename should return default")
    }

}
