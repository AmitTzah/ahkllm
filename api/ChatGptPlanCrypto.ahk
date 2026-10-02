; ======================================================
; ChatGptPlanCrypto.ahk — Windows-native crypto/helpers for ChatGPT OAuth
; ======================================================

class ChatGptPlanCrypto {
    static RandomBytes(byteCount) {
        buf := Buffer(byteCount, 0)
        status := DllCall("Bcrypt\BCryptGenRandom", "Ptr", 0, "Ptr", buf.Ptr, "UInt", buf.Size, "UInt", 0x2, "UInt")
        if status != 0
            throw Error("Secure random generation failed: " status)
        return buf
    }

    static RandomBase64Url(byteCount) {
        return ChatGptPlanCrypto.Base64UrlEncode(ChatGptPlanCrypto.RandomBytes(byteCount))
    }

    static UuidV4() {
        bytes := ChatGptPlanCrypto.RandomBytes(16)
        NumPut("UChar", (NumGet(bytes, 6, "UChar") & 0x0F) | 0x40, bytes, 6)
        NumPut("UChar", (NumGet(bytes, 8, "UChar") & 0x3F) | 0x80, bytes, 8)
        hex := ""
        Loop 16
            hex .= Format("{:02x}", NumGet(bytes, A_Index - 1, "UChar"))
        return SubStr(hex, 1, 8) "-" SubStr(hex, 9, 4) "-" SubStr(hex, 13, 4) "-" SubStr(hex, 17, 4) "-" SubStr(hex, 21, 12)
    }

    static Utf8Buffer(text) {
        size := StrPut(String(text), "UTF-8") - 1
        ; StrPut writes a terminator, so reserve one extra byte but expose only
        ; the actual UTF-8 payload size to callers.
        storage := Buffer(size, 0)
        if size
            StrPut(String(text), storage, size, "UTF-8")
        return storage
    }

    static Utf8FromBuffer(buf) {
        return !IsObject(buf) || !buf.Size ? "" : StrGet(buf.Ptr, buf.Size, "UTF-8")
    }

    static Base64UrlEncode(buf) {
        if !IsObject(buf) || !buf.Size
            return ""
        required := 0
        flags := 0x40000001 ; BASE64 | NOCRLF
        if !DllCall("Crypt32\CryptBinaryToStringA", "Ptr", buf.Ptr, "UInt", buf.Size, "UInt", flags, "Ptr", 0, "UInt*", &required)
            throw OSError(A_LastError, "Base64 encoding failed")
        out := Buffer(required, 0)
        if !DllCall("Crypt32\CryptBinaryToStringA", "Ptr", buf.Ptr, "UInt", buf.Size, "UInt", flags, "Ptr", out.Ptr, "UInt*", &required)
            throw OSError(A_LastError, "Base64 encoding failed")
        value := StrGet(out.Ptr, required, "UTF-8")
        value := StrReplace(StrReplace(value, "+", "-"), "/", "_")
        return RTrim(value, "=")
    }

    static Base64UrlDecode(text) {
        value := StrReplace(StrReplace(String(text), "-", "+"), "_", "/")
        remainder := Mod(StrLen(value), 4)
        if remainder
            value .= SubStr("====", 1, 4 - remainder)
        size := 0
        if !DllCall("Crypt32\CryptStringToBinaryW", "WStr", value, "UInt", StrLen(value), "UInt", 0x1, "Ptr", 0, "UInt*", &size, "Ptr", 0, "Ptr", 0)
            throw Error("Base64url decoding failed.")
        buf := Buffer(size, 0)
        if !DllCall("Crypt32\CryptStringToBinaryW", "WStr", value, "UInt", StrLen(value), "UInt", 0x1, "Ptr", buf.Ptr, "UInt*", &size, "Ptr", 0, "Ptr", 0)
            throw Error("Base64url decoding failed.")
        buf.Size := size
        return buf
    }

    static Sha256Utf8(text) {
        bytes := ChatGptPlanCrypto.Utf8Buffer(text)
        alg := 0
        hashHandle := 0
        try {
            status := DllCall("Bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &alg, "WStr", "SHA256", "Ptr", 0, "UInt", 0, "UInt")
            if status != 0
                throw Error("BCrypt SHA256 provider failed: " status)

            objectLength := 0
            hashLength := 0
            cbResult := 0
            status := DllCall("Bcrypt\BCryptGetProperty", "Ptr", alg, "WStr", "ObjectLength", "UInt*", &objectLength, "UInt", 4, "UInt*", &cbResult, "UInt", 0, "UInt")
            if status != 0
                throw Error("BCrypt ObjectLength failed: " status)
            status := DllCall("Bcrypt\BCryptGetProperty", "Ptr", alg, "WStr", "HashDigestLength", "UInt*", &hashLength, "UInt", 4, "UInt*", &cbResult, "UInt", 0, "UInt")
            if status != 0
                throw Error("BCrypt HashDigestLength failed: " status)

            hashObject := Buffer(objectLength, 0)
            digest := Buffer(hashLength, 0)
            status := DllCall("Bcrypt\BCryptCreateHash", "Ptr", alg, "Ptr*", &hashHandle, "Ptr", hashObject.Ptr, "UInt", hashObject.Size, "Ptr", 0, "UInt", 0, "UInt", 0, "UInt")
            if status != 0
                throw Error("BCryptCreateHash failed: " status)
            if bytes.Size {
                status := DllCall("Bcrypt\BCryptHashData", "Ptr", hashHandle, "Ptr", bytes.Ptr, "UInt", bytes.Size, "UInt", 0, "UInt")
                if status != 0
                    throw Error("BCryptHashData failed: " status)
            }
            status := DllCall("Bcrypt\BCryptFinishHash", "Ptr", hashHandle, "Ptr", digest.Ptr, "UInt", digest.Size, "UInt", 0, "UInt")
            if status != 0
                throw Error("BCryptFinishHash failed: " status)
            return digest
        } finally {
            if hashHandle
                DllCall("Bcrypt\BCryptDestroyHash", "Ptr", hashHandle)
            if alg
                DllCall("Bcrypt\BCryptCloseAlgorithmProvider", "Ptr", alg, "UInt", 0)
        }
    }

    static VerifyRs256(signingInput, signature, jwk) {
        if !IsObject(jwk) || !jwk.Has("n") || !jwk.Has("e")
            return false

        modulus := ChatGptPlanCrypto.Base64UrlDecode(jwk["n"])
        exponent := ChatGptPlanCrypto.Base64UrlDecode(jwk["e"])
        if !modulus.Size || !exponent.Size
            return false

        rsaAlg := 0
        keyHandle := 0
        try {
            status := DllCall("Bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &rsaAlg, "WStr", "RSA", "Ptr", 0, "UInt", 0, "UInt")
            if status != 0
                throw Error("BCrypt RSA provider failed: " status)

            blob := Buffer(24 + exponent.Size + modulus.Size, 0)
            NumPut("UInt", 0x31415352, blob, 0) ; BCRYPT_RSAPUBLIC_MAGIC / RSA1
            NumPut("UInt", modulus.Size * 8, blob, 4)
            NumPut("UInt", exponent.Size, blob, 8)
            NumPut("UInt", modulus.Size, blob, 12)
            NumPut("UInt", 0, blob, 16)
            NumPut("UInt", 0, blob, 20)
            DllCall("RtlMoveMemory", "Ptr", blob.Ptr + 24, "Ptr", exponent.Ptr, "UPtr", exponent.Size)
            DllCall("RtlMoveMemory", "Ptr", blob.Ptr + 24 + exponent.Size, "Ptr", modulus.Ptr, "UPtr", modulus.Size)

            status := DllCall(
                "Bcrypt\BCryptImportKeyPair",
                "Ptr", rsaAlg, "Ptr", 0, "WStr", "RSAPUBLICBLOB",
                "Ptr*", &keyHandle, "Ptr", blob.Ptr, "UInt", blob.Size, "UInt", 0, "UInt"
            )
            if status != 0
                throw Error("BCryptImportKeyPair failed: " status)

            digest := ChatGptPlanCrypto.Sha256Utf8(signingInput)
            algName := "SHA256"
            paddingInfo := Buffer(A_PtrSize, 0)
            NumPut("Ptr", StrPtr(algName), paddingInfo, 0)
            status := DllCall(
                "Bcrypt\BCryptVerifySignature",
                "Ptr", keyHandle,
                "Ptr", paddingInfo.Ptr,
                "Ptr", digest.Ptr, "UInt", digest.Size,
                "Ptr", signature.Ptr, "UInt", signature.Size,
                "UInt", 0x2,
                "UInt"
            )
            return status = 0
        } finally {
            if keyHandle
                DllCall("Bcrypt\BCryptDestroyKey", "Ptr", keyHandle)
            if rsaAlg
                DllCall("Bcrypt\BCryptCloseAlgorithmProvider", "Ptr", rsaAlg, "UInt", 0)
        }
    }

    static ProtectText(text) {
        input := ChatGptPlanCrypto.Utf8Buffer(text)
        inBlob := ChatGptPlanCrypto._DataBlob(input)
        outBlob := Buffer(A_PtrSize = 8 ? 16 : 8, 0)
        ok := DllCall(
            "Crypt32\CryptProtectData",
            "Ptr", inBlob.Ptr,
            "WStr", "AhkLLM ChatGPT plan credentials",
            "Ptr", 0, "Ptr", 0, "Ptr", 0,
            "UInt", 0x1,
            "Ptr", outBlob.Ptr,
            "Int"
        )
        if !ok
            throw OSError(A_LastError, "Windows DPAPI could not protect ChatGPT credentials")

        size := NumGet(outBlob, 0, "UInt")
        ptr := NumGet(outBlob, A_PtrSize = 8 ? 8 : 4, "Ptr")
        try {
            result := Buffer(size, 0)
            if size
                DllCall("RtlMoveMemory", "Ptr", result.Ptr, "Ptr", ptr, "UPtr", size)
            return result
        } finally {
            if ptr
                DllCall("LocalFree", "Ptr", ptr)
        }
    }

    static UnprotectText(bytes) {
        inBlob := ChatGptPlanCrypto._DataBlob(bytes)
        outBlob := Buffer(A_PtrSize = 8 ? 16 : 8, 0)
        ok := DllCall(
            "Crypt32\CryptUnprotectData",
            "Ptr", inBlob.Ptr,
            "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0,
            "UInt", 0x1,
            "Ptr", outBlob.Ptr,
            "Int"
        )
        if !ok
            throw OSError(A_LastError, "Windows DPAPI could not unlock ChatGPT credentials")

        size := NumGet(outBlob, 0, "UInt")
        ptr := NumGet(outBlob, A_PtrSize = 8 ? 8 : 4, "Ptr")
        try return size ? StrGet(ptr, size, "UTF-8") : ""
        finally {
            if ptr
                DllCall("LocalFree", "Ptr", ptr)
        }
    }

    static UrlEncode(value) {
        bytes := ChatGptPlanCrypto.Utf8Buffer(String(value))
        out := ""
        Loop bytes.Size {
            b := NumGet(bytes, A_Index - 1, "UChar")
            if (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
                || (b >= 0x30 && b <= 0x39) || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E
                out .= Chr(b)
            else
                out .= "%" Format("{:02X}", b)
        }
        return out
    }

    static UrlDecode(value) {
        value := StrReplace(String(value), "+", " ")
        bytes := []
        i := 1
        while i <= StrLen(value) {
            ch := SubStr(value, i, 1)
            if ch = "%" && i + 2 <= StrLen(value) && RegExMatch(SubStr(value, i + 1, 2), "^[0-9A-Fa-f]{2}$") {
                bytes.Push(Integer("0x" SubStr(value, i + 1, 2)))
                i += 3
                continue
            }
            encoded := ChatGptPlanCrypto.Utf8Buffer(ch)
            Loop encoded.Size
                bytes.Push(NumGet(encoded, A_Index - 1, "UChar"))
            i++
        }
        buf := Buffer(bytes.Length, 0)
        for idx, b in bytes
            NumPut("UChar", b, buf, idx - 1)
        return bytes.Length ? StrGet(buf.Ptr, buf.Size, "UTF-8") : ""
    }

    static UnixNow() {
        return DateDiff(A_NowUTC, "19700101000000", "Seconds")
    }

    static _DataBlob(bytes) {
        blob := Buffer(A_PtrSize = 8 ? 16 : 8, 0)
        NumPut("UInt", bytes.Size, blob, 0)
        NumPut("Ptr", bytes.Size ? bytes.Ptr : 0, blob, A_PtrSize = 8 ? 8 : 4)
        return blob
    }
}
