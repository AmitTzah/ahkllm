; ----------------------------------------------------
; InlineRequestRunner tests — verify _GetHighlightParams
; computation logic (normalization, RTrim, line splitting)
; ----------------------------------------------------

class InlineRequestRunnerTest {

    static _Params(text) {
        cleanText := StrReplace(StrReplace(text, "`r`n", "`n"), "`r", "`n")
        cleanText := RTrim(cleanText, "`n")
        lines := StrSplit(cleanText, "`n")
        return { lineCount: lines.Length, firstLineLen: lines.Length > 0 ? StrLen(lines[1]) : 0 }
    }

    SingleLine_Simple() {
        p := InlineRequestRunnerTest._Params("hello")
        if (p.lineCount != 1)
            throw Error("lineCount: " p.lineCount)
        if (p.firstLineLen != 5)
            throw Error("firstLineLen: " p.firstLineLen)
    }

    SingleLine_Empty() {
        p := InlineRequestRunnerTest._Params("")
        if (p.lineCount != 0)
            throw Error("lineCount: " p.lineCount)
        ; firstLineLen is 0 for empty — StrSplit("") returns []
        if (p.firstLineLen != 0)
            throw Error("firstLineLen: " p.firstLineLen)
    }

    MultiLine_LF() {
        p := InlineRequestRunnerTest._Params("line1`nline2`nline3")
        if (p.lineCount != 3)
            throw Error("lineCount: " p.lineCount)
        if (p.firstLineLen != 5)
            throw Error("firstLineLen: " p.firstLineLen)
    }

    MultiLine_CRLF() {
        p := InlineRequestRunnerTest._Params("line1`r`nline2`r`nline3")
        if (p.lineCount != 3)
            throw Error("lineCount: " p.lineCount " (CRLF)")
    }

    TrailingNewline_Stripped() {
        p := InlineRequestRunnerTest._Params("hello`n")
        if (p.lineCount != 1)
            throw Error("lineCount: " p.lineCount " (trailing LF stripped)")
    }

    TrailingCRLF_Stripped() {
        p := InlineRequestRunnerTest._Params("hello`r`n")
        if (p.lineCount != 1)
            throw Error("lineCount: " p.lineCount " (trailing CRLF stripped)")
    }

    MultiLine_TrailingNewline() {
        p := InlineRequestRunnerTest._Params("a`nb`n")
        if (p.lineCount != 2)
            throw Error("lineCount: " p.lineCount " (expected 2)")
    }

    BareCR_Normalized() {
        p := InlineRequestRunnerTest._Params("line1`rline2`rline3")
        if (p.lineCount != 3)
            throw Error("lineCount: " p.lineCount " (bare CR)")
    }

    MixedLineEndings() {
        p := InlineRequestRunnerTest._Params("a`r`nb`rc")
        if (p.lineCount != 3)
            throw Error("lineCount: " p.lineCount " (mixed)")
    }

    SingleCharacter() {
        p := InlineRequestRunnerTest._Params("x")
        if (p.lineCount != 1)
            throw Error("lineCount: " p.lineCount)
        if (p.firstLineLen != 1)
            throw Error("firstLineLen: " p.firstLineLen)
    }

    OnlyNewlines_Stripped() {
        p := InlineRequestRunnerTest._Params("`n`n`n")
        if (p.lineCount != 0)
            throw Error("lineCount: " p.lineCount " (all stripped)")
        if (p.firstLineLen != 0)
            throw Error("firstLineLen: " p.firstLineLen)
    }

    Regression_RealisticFIM() {
        p := InlineRequestRunnerTest._Params("    return result`n}`n")
        if (p.lineCount != 2)
            throw Error("lineCount: " p.lineCount " (realistic FIM)")
        if (p.firstLineLen != 17)
            throw Error("firstLineLen: " p.firstLineLen)
    }
}

RegisterTestClass("InlineRequestRunnerTest")
