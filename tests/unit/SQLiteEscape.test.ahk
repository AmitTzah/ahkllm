; ======================================================
; SQLiteEscape.test.ahk — Regression tests for SQLite.Escape()
;
; Covers bug #6 from the bug registry:
;   #6: SQLite.Escape() doubled " → "" (removed the doubling)
; ======================================================

class SQLiteEscapeTest {

    static __New() {
        RegisterTestClass("SQLiteEscapeTest")
    }

    ; ---- Bug #6: " should NOT be doubled ----

    Escape_DoesNotDoubleQuotes() {
        dq := Chr(34)
        input := "He said " dq "hello" dq
        result := SQLite.Escape(input)
        if result != input
            throw Error("Double quotes were modified! Input='" input "', Output='" result "'")
    }

    Escape_StillEscapesSingleQuotes() {
        input := "It's working"
        result := SQLite.Escape(input)
        expected := "It''s working"
        if result != expected
            throw Error("Single quotes not escaped correctly! Expected='" expected "', Got='" result "'")
    }

    Escape_MultipleSingleQuotes() {
        ; RegExReplace("'+", "''") collapses any run of ' to exactly two ''
        input := "x'''y"
        result := SQLite.Escape(input)
        expected := "x''y"
        if result != expected
            throw Error("Multiple single quotes not escaped! Expected='" expected "', Got='" result "'")
    }

    ; ---- SQL roundtrip: write with Escape, read back ----

    Escape_SQLRoundtrip_PreservesQuotes() {
        dq := Chr(34)
        testInput := "He said " dq "hello world" dq " and it's fine"

        ; Use in-memory SQLite
        db := SQLite(":memory:")
        db.Exec("CREATE TABLE escape_test (content TEXT);")

        safeContent := SQLite.Escape(testInput)
        db.Exec("INSERT INTO escape_test (content) VALUES('" safeContent "');")

        table := db.Exec("SELECT content FROM escape_test;")
        output := table.rows[1].content

        if output != testInput
            throw Error("SQL roundtrip corrupted text! Input='" testInput "', Output='" output "'")
    }

    Escape_SQLRoundtrip_MultipleQuotes() {
        dq := Chr(34)
        testInput := dq "nested " dq "quotes" dq " here" dq

        db := SQLite(":memory:")
        db.Exec("CREATE TABLE escape_test2 (content TEXT);")

        safeContent := SQLite.Escape(testInput)
        db.Exec("INSERT INTO escape_test2 (content) VALUES('" safeContent "');")

        table := db.Exec("SELECT content FROM escape_test2;")
        output := table.rows[1].content

        if output != testInput
            throw Error("Nested quotes corrupted! Input='" testInput "', Output='" output "'")
    }

    ; ---- Edge case: empty string ----

    Escape_EmptyString() {
        result := SQLite.Escape("")
        if result != ""
            throw Error("Empty string should stay empty, got '" result "'")
    }

    ; ---- Edge case: string with only quotes ----

    Escape_OnlyQuotes() {
        dq := Chr(34)
        input := dq dq dq  ; three double quotes
        result := SQLite.Escape(input)
        if result != input
            throw Error("Three quotes were modified! Input length=" StrLen(input) ", Output length=" StrLen(result))
    }
}
