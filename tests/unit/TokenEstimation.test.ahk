; ======================================================
; TokenEstimation.test.ahk — Unit tests for TokenEstimation.ahk
; ======================================================

class TokenEstimationTest {

    static __New() {
        RegisterTestClass("TokenEstimationTest")
    }

    ; ----------------------------------------------------
    ; Estimate — character-based token estimation (~4 chars/token)
    ; ----------------------------------------------------
    Estimate_EmptyString_ReturnsAtLeastOne() {
        result := TokenEstimation.Estimate("")
        if result < 1
            throw Error("Expected >= 1, got " result)
    }

    Estimate_ShortText_ReturnsAtLeastOne() {
        result := TokenEstimation.Estimate("hi")
        if result < 1
            throw Error("Expected >= 1, got " result)
    }

    Estimate_LongerText_Proportional() {
        short := TokenEstimation.Estimate("hello world")
        longText := "hello world extra text extra text extra text extra text extra text extra text extra text extra text extra text extra text extra text extra text extra text extra text extra text"
        long := TokenEstimation.Estimate(longText)
        if long <= short
            throw Error("Longer text should have higher estimate: " short " vs " long)
    }

    Estimate_Consistent() {
        r1 := TokenEstimation.Estimate("The quick brown fox jumps over the lazy dog")
        r2 := TokenEstimation.Estimate("The quick brown fox jumps over the lazy dog")
        if r1 != r2
            throw Error("Same text should give same estimate: " r1 " vs " r2)
    }
}
