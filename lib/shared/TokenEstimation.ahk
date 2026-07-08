; ----------------------------------------------------
; TokenEstimation — Character-based token estimation
;
; Uses ~4 chars ≈ 1 token (standard English estimate).
; Replaces 4 inline StrLen(s)/4 calculations.
; ----------------------------------------------------

class TokenEstimation {
    ; Estimate token count from string length. Min 1.
    static Estimate(str) {
        len := StrLen(str)
        return len > 3 ? Round(len / 4) : 1
    }
}
