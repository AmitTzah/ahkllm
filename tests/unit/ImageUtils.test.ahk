; ======================================================
; ImageUtils.test.ahk — Regression tests for base64 encode/decode
;
; Covers bugs #2, #3, #4, #5 from the bug registry:
;   #2: Base64 decode returns 0 bytes (CryptStringToBinaryA→W)
;   #3: _Base64Encode crashes on Buffer input
;   #4: _Base64Encode crashes on large binary
;   #5: _Base64ToStr returns empty from DB (CryptStringToBinaryA→W)
; ======================================================

class ImageUtilsTest {

    static __New() {
        RegisterTestClass("ImageUtilsTest")
    }

    ; ---- Bug #2: Base64 decode works on UTF-16 input ----

    _Base64Decode_HandlesStandardInput() {
        ; "Hello" in base64 = "SGVsbG8="
        result := ImageUtils._Base64Decode("SGVsbG8=")
        if !IsObject(result) || !(result is Buffer)
            throw Error("Expected Buffer, got " Type(result))
        if result.Size != 5
            throw Error("Expected 5 bytes, got " result.Size)
        text := StrGet(result, 5, "UTF-8")
        if text != "Hello"
            throw Error("Expected 'Hello', got '" text "'")
    }

    _Base64Decode_HandlesUnicode() {
        ; "café" in UTF-8 base64
        result := ImageUtils._Base64Decode("Y2Fmw6k=")
        if !result || result.Size != 5
            throw Error("Expected 5 bytes for café, got " (result ? result.Size : 0))
        text := StrGet(result, 5, "UTF-8")
        if text != "café"
            throw Error("Expected 'café', got '" text "'")
    }

    _Base64Decode_ReturnsFalseOnInvalid() {
        result := ImageUtils._Base64Decode("!!!invalid!!!")
        if result
            throw Error("Expected false/empty for invalid base64")
    }

    ; ---- Bug #3: _Base64Encode handles Buffer input ----

    _Base64Encode_BufferInput() {
        ; Create a small Buffer and encode it
        buf := Buffer(5)
        StrPut("Hello", buf, 5, "UTF-8")
        result := ImageUtils._Base64Encode(buf, 5)
        if result != "SGVsbG8="
            throw Error("Expected 'SGVsbG8=', got '" result "'")
    }

    _Base64Encode_StringInput() {
        ; Also test string input for backward compat
        result := ImageUtils._Base64Encode("A")
        if result != "QQ=="
            throw Error("Expected 'QQ==', got '" result "'")
    }

    ; ---- Bug #4: _Base64Encode handles large binary data ----

    _Base64Encode_LargeBinaryData() {
        ; Create ~500KB buffer with varied content (avoid all-zeros)
        size := 500 * 1024
        buf := Buffer(size)
        Loop size {
            NumPut("UChar", Mod(A_Index, 256), buf, A_Index - 1)
        }

        result := ImageUtils._Base64Encode(buf, size)
        if !result || StrLen(result) < 100
            throw Error("Large binary encode failed: result length=" (result ? StrLen(result) : 0))

        ; Roundtrip: decode should give back the same binary
        decoded := ImageUtils._Base64Decode(result)
        if !decoded || decoded.Size != size
            throw Error("Large binary roundtrip failed: decoded size=" (decoded ? decoded.Size : 0) " expected=" size)

        ; Verify first 100 bytes match
        Loop 100 {
            origByte := NumGet(buf, A_Index - 1, "UChar")
            decByte := NumGet(decoded, A_Index - 1, "UChar")
            if origByte != decByte
                throw Error("Byte mismatch at offset " (A_Index - 1) ": " origByte " vs " decByte)
        }
    }

    ; ---- Bug #5: Base64 roundtrip for large text (simulates AttachmentRepo flow) ----

    _Base64_Roundtrip_LargeText() {
        ; Simulate the extracted_text flow: string → UTF-8 → base64 → SQL → base64 → UTF-8 → string
        ; Build a large text with " characters (the corruption trigger)
        parts := []
        Loop 200 {
            parts.Push('Line ' A_Index ': He said "hello" and she replied "goodbye".')
        }
        input := ""
        for part in parts
            input .= part "`n"
        input := RTrim(input, "`n")

        ; Encode (as AttachmentRepo._StrToBase64 does)
        size := StrPut(input, "UTF-8") - 1
        buf := Buffer(size)
        StrPut(input, buf, size, "UTF-8")
        requiredSize := 0
        DllCall("Crypt32.dll\CryptBinaryToStringA", "Ptr", buf, "UInt", size, "UInt", 0x1, "Ptr", 0, "UIntP", &requiredSize)
        if requiredSize <= 0
            throw Error("Base64 encode failed: requiredSize=" requiredSize)
        b64Buf := Buffer(requiredSize)
        DllCall("Crypt32.dll\CryptBinaryToStringA", "Ptr", buf, "UInt", size, "UInt", 0x1, "Ptr", b64Buf, "UIntP", &requiredSize)
        encoded := StrGet(b64Buf, requiredSize, "UTF-8")
        encoded := StrReplace(StrReplace(encoded, "`r`n", ""), "`n", "")

        ; Decode (as AttachmentRepo._Base64ToStr does — MUST use W variant for AHK UTF-16)
        decSize := 0
        DllCall("Crypt32.dll\CryptStringToBinaryW", "Ptr", StrPtr(encoded), "UInt", StrLen(encoded),
            "UInt", 0x1, "Ptr", 0, "UIntP", &decSize, "Ptr", 0, "Ptr", 0)
        if decSize <= 0
            throw Error("Base64 decode failed: decSize=" decSize)
        decBuf := Buffer(decSize)
        DllCall("Crypt32.dll\CryptStringToBinaryW", "Ptr", StrPtr(encoded), "UInt", StrLen(encoded),
            "UInt", 0x1, "Ptr", decBuf, "UIntP", &decSize, "Ptr", 0, "Ptr", 0)
        output := StrGet(decBuf, decSize, "UTF-8")

        if output != input
            throw Error("Large text roundtrip failed: output length=" StrLen(output) " input length=" StrLen(input))

        ; Verify no " corruption
        if InStr(output, '""')
            throw Error("Double-quote corruption detected in roundtrip!")
    }

    _Base64_Roundtrip_PreservesQuotes() {
        ; Direct test: text with quotes should survive encode→decode
        input := 'He said "hello world" and "goodbye"'
        size := StrPut(input, "UTF-8") - 1
        buf := Buffer(size)
        StrPut(input, buf, size, "UTF-8")

        encoded := ImageUtils._Base64Encode(buf, size)
        decoded := ImageUtils._Base64Decode(encoded)
        output := StrGet(decoded, decoded.Size, "UTF-8")

        if output != input
            throw Error("Quote preservation failed: '" output "' vs '" input "'")
    }
}
