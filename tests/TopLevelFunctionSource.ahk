; Read complete top-level AHK functions for source-order regression checks.
; Do not truncate a function at an arbitrary character count.
class TopLevelFunctionSource {
    static Read(source, functionName) {
        header := "m)^" functionName "\([^\r\n]*\) \{"
        if !RegExMatch(source, header, &first)
            throw Error("Function not found in source: " functionName)
        nextHeader := "m)^[A-Za-z_]\w*\([^\r\n]*\) \{"
        end := RegExMatch(source, nextHeader, &next, first.Pos + first.Len)
        return SubStr(source, first.Pos, end ? end - first.Pos : StrLen(source) - first.Pos + 1)
    }
}
