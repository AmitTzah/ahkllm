; ======================================================
; ImageUtils.ahk — Image file I/O and clipboard capture
;
; Base64 decode/save, clipboard bitmap to PNG, file cleanup.
; Uses GDI+ (gdiplus.dll) for screen capture and bitmap save.
; ======================================================

class ImageUtils {

    ; Ensure the attachments directory exists under AppData.
    static EnsureAttachmentDir() {
        dir := A_AppData "\LLM-AutoHotkey-Assistant\attachments"
        if !DirExist(dir)
            DirCreate(dir)
        return dir
    }

    ; Decode base64 data and write to a file in the attachments directory.
    ; If contentHash is provided, uses hash-based filename for deduplication.
    ; Returns the relative file path.
    static SaveBase64ToFile(base64Data, messageId, filename, contentHash := "") {
        debugLog("[IMGUTIL] SaveBase64ToFile: filename=" filename " base64Len=" StrLen(base64Data) " hash=" (contentHash ? SubStr(contentHash, 1, 8) "..." : "none"), "AttachPipeline")
        ImageUtils.EnsureAttachmentDir()
        safeExt := ""
        SplitPath(filename, , , &ext)
        if ext
            safeExt := "." ext

        ; Content-addressable storage: use SHA-256 hash as filename
        if contentHash {
            safeName := contentHash safeExt
            filePath := "attachments\" safeName
            fullPath := A_AppData "\LLM-AutoHotkey-Assistant\" filePath
            ; If file already exists (dedup hit), skip write
            if FileExist(fullPath) {
                debugLog("[IMGUTIL] SaveBase64ToFile: DEDUP HIT, file exists at " fullPath, "AttachPipeline")
                return filePath
            }
        } else {
            ; Fallback: counter-based name for screenshots and legacy
            safeName := messageId "_att" A_TickCount safeExt
            filePath := "attachments\" safeName
            fullPath := A_AppData "\LLM-AutoHotkey-Assistant\" filePath
        }
        debugLog("[IMGUTIL] SaveBase64ToFile: fullPath=" fullPath, "AttachPipeline")

        ; Decode base64 to binary and write to file
        binData := ImageUtils._Base64Decode(base64Data)
        if binData {
            debugLog("[IMGUTIL] SaveBase64ToFile: decoded " binData.Size " bytes, writing to disk", "AttachPipeline")
            f := FileOpen(fullPath, "w")
            f.RawWrite(binData, binData.Size)
            f.Close()
            debugLog("[IMGUTIL] SaveBase64ToFile: file written, exists=" FileExist(fullPath), "AttachPipeline")
        } else {
            debugLog("[IMGUTIL] SaveBase64ToFile: _Base64Decode returned false", "AttachPipeline")
            return ""
        }

        debugLog("[IMGUTIL] SaveBase64ToFile result: filePath=" filePath, "AttachPipeline")
        return filePath
    }

    ; Capture the entire screen to a PNG file using GDI+.
    ; No clipboard or PrintScreen key — works regardless of Windows settings.
    static CaptureScreen(messageId) {
        ImageUtils.EnsureAttachmentDir()
        ImageUtils._EnsureGdiPlusInitialized()
        fileName := messageId "_screenshot.png"
        filePath := "attachments\" fileName
        fullPath := A_AppData "\LLM-AutoHotkey-Assistant\" filePath

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

    ; Capture clipboard bitmap (from PrintScreen) and save as PNG to attachments/.
    ; Returns the relative file path.
    static SaveClipboardToFile(messageId) {
        ImageUtils.EnsureAttachmentDir()
        fileName := messageId "_screenshot.png"
        filePath := "attachments\" fileName
        fullPath := A_AppData "\LLM-AutoHotkey-Assistant\" filePath

        ; Use GDI+ via built-in SavePictureToFile approach.
        ; AHK v2 can save clipboard content using FileAppend for PNG if
        ; we first get the bitmap onto clipboard in PNG format.
        ; Approach: use Send("{PrintScreen}") then save clipboard.
        ; The clipboard should contain a bitmap at this point.
        ; Convert to PNG via GDI+ SaveBitmapToFile (using built-in Gdip functions)
        try {
            ImageUtils._SaveClipboardBitmapToPNG(fullPath)
        } catch Error as e {
            return ""
        }
        return filePath
    }

    ; Delete a file from disk (full relative path from attachments dir).
    static DeleteFile(filePath) {
        fullPath := A_AppData "\LLM-AutoHotkey-Assistant\" filePath
        try FileDelete(fullPath)
    }

    ; Copy a file to a new path with a new message ID in the filename.
    static CopyFile(srcPath, destMsgId) {
        fullSrc := A_AppData "\LLM-AutoHotkey-Assistant\" srcPath
        SplitPath(srcPath, &fileName)
        ; Replace old message ID with new one in filename
        ; Filename format: msg_OLDID_rest.ext → msg_NEWID_rest.ext
        newFileName := ""
        ; Find the message ID portion (between "msg_" and the next "_")
        if InStr(fileName, "msg_") {
            prefixEnd := InStr(fileName, "_", , , 2)  ; second underscore
            if prefixEnd {
                newFileName := "msg_" destMsgId "_" SubStr(fileName, prefixEnd + 1)
            } else {
                newFileName := "msg_" destMsgId "_" SubStr(fileName, InStr(fileName, "_") + 1)
            }
        } else {
            newFileName := "msg_" destMsgId "_" fileName
        }
        newPath := "attachments\" newFileName
        fullDest := A_AppData "\LLM-AutoHotkey-Assistant\" newPath
        if FileExist(fullSrc)
            try FileCopy(fullSrc, fullDest, true)
        return newPath
    }

    ; Read file and base64-encode its content.
    ; Used by buildRequest to read attachment files for API calls.
    static ReadAndEncode(filePath) {
        fullPath := A_AppData "\LLM-AutoHotkey-Assistant\" filePath
        debugLog("[IMGUTIL] ReadAndEncode: fullPath=" fullPath, "AttachPipeline")
        if !FileExist(fullPath) {
            debugLog("[IMGUTIL] ReadAndEncode: FILE NOT FOUND", "AttachPipeline")
            return ""
        }
        fileSize := FileGetSize(fullPath)
        debugLog("[IMGUTIL] ReadAndEncode: fileSize=" fileSize, "AttachPipeline")
        if !fileSize
            return ""
        buf := Buffer(fileSize)
        f := FileOpen(fullPath, "r")
        f.RawRead(buf, fileSize)
        f.Close()
        debugLog("[IMGUTIL] ReadAndEncode: read " fileSize " bytes, encoding to base64", "AttachPipeline")
        encoded := ""
        try {
            encoded := ImageUtils._Base64Encode(buf, fileSize)
            debugLog("[IMGUTIL] ReadAndEncode: encoded len=" StrLen(encoded), "AttachPipeline")
        } catch Error as e {
            debugLog("[IMGUTIL] ReadAndEncode: _Base64Encode crashed: " e.Message, "AttachPipeline")
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
        debugLog("[IMGUTIL] _Base64Decode: inputLen=" StrLen(b64) " requiredSize=" requiredSize, "AttachPipeline")
        if requiredSize <= 0 {
            debugLog("[IMGUTIL] _Base64Decode: FAILED — requiredSize=" requiredSize, "AttachPipeline")
            return ""
        }
        ; Allocate buffer and decode — return Buffer for binary safety
        buf := Buffer(requiredSize)
        DllCall("Crypt32.dll\CryptStringToBinaryW", "Ptr", StrPtr(b64), "UInt", StrLen(b64),
            "UInt", CRYPT_STRING_BASE64, "Ptr", buf, "UIntP", &requiredSize, "Ptr", 0, "Ptr", 0)
        debugLog("[IMGUTIL] _Base64Decode: decoded " requiredSize " bytes", "AttachPipeline")
        return buf
    }

    static _SaveClipboardBitmapToPNG(filePath) {
        ; Use GDI+ to save clipboard bitmap as PNG
        ; Requires gdiplus.dll (available on all Windows)
        ImageUtils._EnsureGdiPlusInitialized()

        ; Open clipboard
        if !DllCall("OpenClipboard", "Ptr", 0)
            throw Error("Failed to open clipboard")
        hBitmap := DllCall("GetClipboardData", "UInt", 2, "Ptr")  ; CF_BITMAP = 2
        if !hBitmap {
            DllCall("CloseClipboard")
            throw Error("No bitmap on clipboard")
        }

        ; Create GDI+ bitmap from HBITMAP
        DllCall("gdiplus.dll\GdipCreateBitmapFromHBITMAP", "Ptr", hBitmap, "Ptr", 0, "PtrP", &pBitmap := 0)
        DllCall("CloseClipboard")

        if !pBitmap
            throw Error("Failed to create GDI+ bitmap")

        ; Get PNG encoder CLSID
        pngEncoder := ImageUtils._GetEncoderCLSID("image/png")
        ; Save to file
        DllCall("gdiplus.dll\GdipSaveImageToFile", "Ptr", pBitmap, "Ptr", StrPtr(filePath), "Ptr", pngEncoder, "Ptr", 0)
        DllCall("gdiplus.dll\GdipDisposeImage", "Ptr", pBitmap)
    }


    ; Initialize GDI+ once (shared by CaptureScreen and _SaveClipboardBitmapToPNG).
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
