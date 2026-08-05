; ======================================================
; ImageUtils.ahk — Image file I/O and clipboard capture
;
; Base64 decode/save, clipboard bitmap to PNG, file cleanup.
; Uses GDI+ (gdiplus.dll) for screen capture and bitmap save.
; ======================================================

#Include DebugLog.ahk
#Include AppInfo.ahk

class ImageUtils {

    ; Ensure the attachments directory exists under AppData.
    static EnsureAttachmentDir() {
        dir := AppInfo.DataDir "\attachments"
        if !DirExist(dir)
            DirCreate(dir)
        return dir
    }

    ; Decode base64 data and write to a file in the attachments directory.
    ; If contentHash is provided, uses hash-based filename for deduplication.
    ; Returns the relative file path.
    static SaveBase64ToFile(base64Data, messageId, filename, contentHash := "") {
        ImageUtils.EnsureAttachmentDir()
        safeExt := ""
        SplitPath(filename, , , &ext)
        if ext
            safeExt := "." ext

        ; Content-addressable storage: use SHA-256 hash as filename
        if contentHash {
            safeName := contentHash safeExt
            filePath := "attachments\" safeName
            fullPath := AppInfo.DataDir "\" filePath
            ; If file already exists (dedup hit), skip write
            if FileExist(fullPath) {
                return filePath
            }
        } else {
            ; Fallback: counter-based name for screenshots and legacy
            safeName := messageId "_att" A_TickCount safeExt
            filePath := "attachments\" safeName
            fullPath := AppInfo.DataDir "\" filePath
        }
        ; Decode base64 to binary and write to file
        binData := ImageUtils._Base64Decode(base64Data)
        if binData {
            f := FileOpen(fullPath, "w")
            f.RawWrite(binData, binData.Size)
            f.Close()
        } else {
            return ""
        }

        return filePath
    }

    ; Capture the entire screen to a PNG file using GDI+.
    ; No clipboard or PrintScreen key — works regardless of Windows settings.
    static CaptureScreen(messageId) {
        ImageUtils.EnsureAttachmentDir()
        ImageUtils._EnsureGdiPlusInitialized()
        fileName := messageId "_screenshot.png"
        filePath := "attachments\" fileName
        fullPath := AppInfo.DataDir "\" filePath

        ; Get screen dimensions
        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        screenW := DllCall("GetDeviceCaps", "Ptr", hdcScreen, "Int", 8)   ; HORZRES
        screenH := DllCall("GetDeviceCaps", "Ptr", hdcScreen, "Int", 10)  ; VERTRES

        ; Create compatible DC and bitmap
        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        hBitmap := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", screenW, "Int", screenH, "Ptr")
        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hBitmap)

        ; Copy screen into bitmap
        DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", screenW, "Int", screenH,
            "Ptr", hdcScreen, "Int", 0, "Int", 0, "UInt", 0x00CC0020)  ; SRCCOPY

        ; Convert to GDI+ bitmap and save as PNG
        pBitmap := 0
        DllCall("gdiplus.dll\GdipCreateBitmapFromHBITMAP", "Ptr", hBitmap, "Ptr", 0, "PtrP", &pBitmap)
        if pBitmap {
            pngEncoder := ImageUtils._GetEncoderCLSID("image/png")
            DllCall("gdiplus.dll\GdipSaveImageToFile", "Ptr", pBitmap, "Ptr", StrPtr(fullPath), "Ptr", pngEncoder, "Ptr", 0)
            DllCall("gdiplus.dll\GdipDisposeImage", "Ptr", pBitmap)
        }

        ; Cleanup
        DllCall("DeleteDC", "Ptr", hdcMem)
        DllCall("DeleteObject", "Ptr", hBitmap)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

        return pBitmap ? filePath : ""
    }

    ; Read file and base64-encode its content.
    ; Used by buildRequest to read attachment files for API calls.
    static ReadAndEncode(filePath) {
        fullPath := AppInfo.DataDir "\" filePath
        if !FileExist(fullPath) {
            return ""
        }
        fileSize := FileGetSize(fullPath)
        if !fileSize
            return ""
        buf := Buffer(fileSize)
        f := FileOpen(fullPath, "r")
        f.RawRead(buf, fileSize)
        f.Close()
        encoded := ""
        try {
            encoded := ImageUtils._Base64Encode(buf, fileSize)
        } catch Error as e {
            debugLog("ImageUtils.ReadAndEncode _Base64Encode crashed: " e.Message, "ErrorHandler")
        }
        return encoded
    }

    ; ---- Private helpers ----

    static _Base64Encode(raw, size := 0) {
        ; Use CryptBinaryToStringA (Crypt32.dll) for base64 encode.
        ; Base64 output is always ASCII, so the A variant is correct —
        ; requiredSize is in bytes and matches Buffer() allocation directly.
        ; CRYPT_STRING_BASE64 = 1
        static CRYPT_STRING_BASE64 := 0x1
        if !size
            size := raw is Buffer ? raw.Size : StrLen(raw)
        requiredSize := 0
        DllCall("Crypt32.dll\CryptBinaryToStringA", "Ptr", raw is Buffer ? raw.Ptr : StrPtr(raw), "UInt", size,
            "UInt", CRYPT_STRING_BASE64, "Ptr", 0, "UIntP", &requiredSize)
        if requiredSize <= 0
            return ""
        ; requiredSize is in bytes (ANSI output) — matches Buffer byte count
        buf := Buffer(requiredSize)
        DllCall("Crypt32.dll\CryptBinaryToStringA", "Ptr", raw is Buffer ? raw.Ptr : StrPtr(raw), "UInt", size,
            "UInt", CRYPT_STRING_BASE64, "Ptr", buf, "UIntP", &requiredSize)
        ; Strip trailing CRLF that CryptBinaryToString adds
        result := StrGet(buf, requiredSize, "UTF-8")
        result := StrReplace(result, "`r`n", "")
        result := StrReplace(result, "`n", "")
        return result
    }

    static _Base64Decode(b64) {
        ; Use CryptStringToBinaryW (Crypt32.dll) for base64 decode
        ; CRYPT_STRING_BASE64 = 1
        static CRYPT_STRING_BASE64 := 0x1
        ; First call to get required size
        requiredSize := 0
        DllCall("Crypt32.dll\CryptStringToBinaryW", "Ptr", StrPtr(b64), "UInt", StrLen(b64),
            "UInt", CRYPT_STRING_BASE64, "Ptr", 0, "UIntP", &requiredSize, "Ptr", 0, "Ptr", 0)
        if requiredSize <= 0 {
            return ""
        }
        ; Allocate buffer and decode — return Buffer for binary safety
        buf := Buffer(requiredSize)
        DllCall("Crypt32.dll\CryptStringToBinaryW", "Ptr", StrPtr(b64), "UInt", StrLen(b64),
            "UInt", CRYPT_STRING_BASE64, "Ptr", buf, "UIntP", &requiredSize, "Ptr", 0, "Ptr", 0)
        return buf
    }

    ; Initialize GDI+ once (used by CaptureScreen).
    static _EnsureGdiPlusInitialized() {
        static GdipInitialized := false
        if !GdipInitialized {
            si := Buffer(24, 0)
            NumPut("UInt", 1, si, 0)
            DllCall("gdiplus.dll\GdiplusStartup", "PtrP", &gdipToken := 0, "Ptr", si, "Ptr", 0)
            GdipInitialized := true
        }
    }

    static _GetEncoderCLSID(mimeType) {
        if mimeType = "image/png" {
            static pngCLSID := "{557CF406-1A04-11D3-9A73-0000F81EF32E}"
            clsidBuf := Buffer(16)
            DllCall("ole32.dll\CLSIDFromString", "Ptr", StrPtr(pngCLSID), "Ptr", clsidBuf)
            return clsidBuf
        }
        return 0
    }
}
