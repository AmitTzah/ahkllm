; ======================================================
; test_sqlite_escape_bug.ahk — Reproduce " doubling bug
;
; Usage: AutoHotkey64.exe test_sqlite_escape_bug.ahk
; ======================================================
#Requires AutoHotkey v2.0.18+
#ErrorStdOut
#SingleInstance Off
#NoTrayIcon

#Include ../../lib/SQLite/SQLite.ahk

dq := Chr(34)
qq := dq dq  ; ""

; Create in-memory DB
db := SQLite(":memory:")
db.Exec("CREATE TABLE test (id INTEGER PRIMARY KEY, content TEXT);")

; Test string containing double quotes
testInput := "He said " dq "hello world" dq " and " dq "goodbye" dq
FileAppend("Input: " testInput "`nInput length: " StrLen(testInput) "`n", "*")

; Escape using SQLite.Escape (the function under test)
safeContent := SQLite.Escape(testInput)
FileAppend("After Escape(): |" safeContent "|`nEscaped length: " StrLen(safeContent) "`n", "*")

; Insert
db.Exec("INSERT INTO test (content) VALUES('" safeContent "');")

; Read back
table := db.Exec("SELECT content FROM test;")
output := table.rows[1].content
FileAppend("After SQL roundtrip: |" output "|`nOutput length: " StrLen(output) "`n", "*")

; Check for corruption
if InStr(output, qq) {
    FileAppend("`n=== BUG CONFIRMED: " dq " doubling detected! ===", "*")
    FileAppend("`n  Input:  |" testInput "|", "*")
    FileAppend("`n  Output: |" output "|`n", "*")
} else {
    FileAppend("`n=== CLEAN: No double-quote corruption. ===", "*")
    FileAppend("`n  Input:  |" testInput "|", "*")
    FileAppend("`n  Output: |" output "|`n", "*")
}

; Also test: does SQLite.Escape double "?
singleDQ := dq
escapedSingle := SQLite.Escape(singleDQ)
FileAppend("`nSQLite.Escape(" dq dq ") = |" escapedSingle "| (length=" StrLen(escapedSingle) ")`n", "*")
FileAppend("The " dq " doubling happens in Escape() itself, before SQL even sees it.`n", "*")
