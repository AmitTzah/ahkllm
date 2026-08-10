; probe-utf8.ahk - Verifies StreamHandler._readFileChunk's UTF-8-RAW read
; semantics for multibyte content (bug-hunt lead #2: "Streamed content can be
; corrupted at UTF-8 multibyte boundaries").
;
; Mirrors the EXACT File calls used by _readFileChunk in
; chat/streaming/StreamHandler.ahk:
;   file := FileOpen(path, "r", "UTF-8-RAW")
;   file.Pos := state.lastPos
;   newContent := file.Read()
;   state.lastPos := file.Pos
;
; Usage: AutoHotkey64.exe probe-utf8.ahk <outFile>
#Requires AutoHotkey v2.0.18+
#ErrorStdOut
#SingleInstance Off
#NoTrayIcon

global outFile := A_Args.Length >= 1 ? A_Args[1] : A_Temp "\utf8_probe_result.txt"
global logLines := []
Log(m) {
    global logLines
    logLines.Push(m)
}
SetTimer(ExitProbe, -15000)
ExitProbe(*) {
    Log("WATCHDOG fired")
    Finish()
    ExitApp(1)
}
OnError((e, m) => (Log("ERROR: " e.Message), Finish(), ExitApp(1)), -1)

Finish() {
    global outFile, logLines
    try FileAppend(Join("`n", logLines), outFile, "UTF-8")
}
Join(sep, arr) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") v
    return out
}

; Write EXACT UTF-8 bytes to a file (no AHK translation involved).
WriteBytes(path, bytes) {
    f := FileOpen(path, "w", "UTF-8-RAW")
    buf := Buffer(bytes.Length)
    for i, b in bytes
        NumPut("UChar", b, buf, i - 1)
    f.RawWrite(buf)
    f.Close()
}

; EXACT copy of StreamHandler._readFileChunk.
_readFileChunk(state) {
    if !FileExist(state.outputFile)
        return ""
    file := FileOpen(state.outputFile, "r", "UTF-8-RAW")
    if !file
        return ""
    file.Pos := state.lastPos
    newContent := file.Read()
    state.lastPos := file.Pos
    file.Close()
    return newContent
}

CharBytes(text) {
    size := StrPut(text, "UTF-8")
    buf := Buffer(size)
    StrPut(text, buf, size, "UTF-8")
    arr := []
    loop size - 1
        arr.Push(NumGet(buf, A_Index - 1, "UChar"))
    return arr
}

; CASE 1: whole multibyte string read in ONE poll (no split). If UTF-8-RAW
; decodes, content round-trips; if it does byte->char, we get mojibake.
Utf8Whole() {
    path := A_Temp "\utf8_whole_" A_TickCount ".tmp"
    text := "h" Chr(0xE9) "llo " Chr(0x3B1) " ok"  ; héllo α ok
    WriteBytes(path, CharBytes(text))
    state := {outputFile: path, lastPos: 0}
    got := _readFileChunk(state)
    FileDelete(path)
    same := (got = text)
    Log("UTF8WHOLE sent=" text)
    Log("UTF8WHOLE got=" got)
    Log("UTF8WHOLE byteLen=" StrPut(got, "UTF-8") " (native len " StrLen(got) ")")
    Log("UTF8WHOLE verdict=" (same ? "OK-roundtrip" : "BUG-present(mojibake)"))
}

; CASE 2: poll boundary splits a multibyte character. First read sees only the
; partial leading bytes of an UTF-8 char; second read resumes at lastPos.
Utf8Split() {
    path := A_Temp "\utf8_split_" A_TickCount ".tmp"
    text := "ab" Chr(0xE9) "cd"  ; ab + é + cd ; é = C3 A9
    bytes := CharBytes(text)
    ; bytes: 61 62 C3 A9 63 64. Write the first 3 (split INSIDE é), read,
    ; then append the rest and resume from lastPos - the poll pattern.
    WriteBytes(path, [bytes[1], bytes[2], bytes[3]])
    state := {outputFile: path, lastPos: 0}
    part1 := _readFileChunk(state)
    pos := state.lastPos
    rest := []
    for i, b in bytes
        if i > 3
            rest.Push(b)
    f := FileOpen(path, "a", "UTF-8-RAW")
    buf := Buffer(rest.Length)
    for i, b in rest
        NumPut("UChar", b, buf, i - 1)
    f.RawWrite(buf)
    f.Close()
    state2 := {outputFile: path, lastPos: pos}
    part2 := _readFileChunk(state2)
    FileDelete(path)
    joined := part1 . part2
    same := (joined = text)
    Log("UTF8SPLIT sent=" text)
    Log("UTF8SPLIT part1=" part1 " part2=" part2 " joined=" joined)
    Log("UTF8SPLIT posAfterFirstRead=" pos " byteLen=" StrPut(joined, "UTF-8"))
    Log("UTF8SPLIT verdict=" (same ? "OK-roundtrip" : "BUG-present(split-mangles)"))
}

Utf8Whole()
Utf8Split()
Finish()
ExitApp(0)
