; ======================================================
; ChatGptPlanCrypto.test.ahk — local crypto primitive tests
; No network or real account material.
; ======================================================

class ChatGptPlanCryptoTest {
    static __New() {
        RegisterTestClass("ChatGptPlanCryptoTest")
    }

    UrlEncoding_RoundTripsUnicodeAndReservedCharacters() {
        value := "alias@example.test / שלום ?&="
        encoded := ChatGptPlanCrypto.UrlEncode(value)
        if InStr(encoded, " ")
            throw Error("OAuth query values must percent-encode spaces")
        decoded := ChatGptPlanCrypto.UrlDecode(encoded)
        if decoded != value
            throw Error("OAuth URL encoding did not round-trip Unicode text")
    }

    Base64Url_RoundTripsBinaryWithoutPadding() {
        raw := Buffer(5, 0)
        NumPut("UChar", 0x00, raw, 0)
        NumPut("UChar", 0xFF, raw, 1)
        NumPut("UChar", 0x10, raw, 2)
        NumPut("UChar", 0x7F, raw, 3)
        NumPut("UChar", 0x80, raw, 4)
        encoded := ChatGptPlanCrypto.Base64UrlEncode(raw)
        if InStr(encoded, "+") || InStr(encoded, "/") || InStr(encoded, "=")
            throw Error("PKCE/JWT base64url output must be URL-safe and unpadded")
        decoded := ChatGptPlanCrypto.Base64UrlDecode(encoded)
        if decoded.Size != raw.Size
            throw Error("base64url round-trip size mismatch")
        Loop raw.Size {
            if NumGet(decoded, A_Index - 1, "UChar") != NumGet(raw, A_Index - 1, "UChar")
                throw Error("base64url round-trip byte mismatch at " A_Index)
        }
    }

    Sha256Utf8_MatchesKnownDigest() {
        digest := ChatGptPlanCrypto.Sha256Utf8("abc")
        encoded := ChatGptPlanCrypto.Base64UrlEncode(digest)
        if encoded != "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0"
            throw Error("SHA-256 helper returned an unexpected digest")
    }

    Dpapi_RoundTripsProtectedTextWithoutPlaintext() {
        value := '{"session":"alpha-value","renewal":"beta-value"}'
        protected := ChatGptPlanCrypto.ProtectText(value)
        if !IsObject(protected) || protected.Size = 0
            throw Error("DPAPI protection returned no ciphertext")
        try asText := StrGet(protected.Ptr, protected.Size, "UTF-8")
        catch
            asText := ""
        if InStr(asText, "alpha-value")
            throw Error("DPAPI ciphertext exposed protected text in plaintext")
        restored := ChatGptPlanCrypto.UnprotectText(protected)
        if restored != value
            throw Error("DPAPI protected data did not round-trip")
    }

    RandomValues_HaveExpectedShape() {
        verifier := ChatGptPlanCrypto.RandomBase64Url(32)
        if StrLen(verifier) < 40 || RegExMatch(verifier, "[^A-Za-z0-9_-]")
            throw Error("PKCE random value is not URL-safe")
        uuid := ChatGptPlanCrypto.UuidV4()
        if !RegExMatch(uuid, "i)^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
            throw Error("host UUID is not RFC4122 version 4 shaped")
    }
}
