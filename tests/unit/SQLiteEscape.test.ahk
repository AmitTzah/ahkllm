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

    ; ---- Query: bound-parameter API (hardening item 1) ----

    Query_BindsValuesAndReturnsSameTableShape() {
        db := SQLite(":memory:")
        db.Query("CREATE TABLE q_test (id TEXT PRIMARY KEY, n INTEGER, r REAL, body TEXT);")
        db.Query("INSERT INTO q_test (id, n, r, body) VALUES(?, ?, ?, ?);", "a'b", 5, 2.5, "hello ' world")
        db.Query("INSERT INTO q_test (id, n, r, body) VALUES(?, ?, ?, ?);", "c", -3, 0.0, "")
        table := db.Query("SELECT id, n, r, body FROM q_test ORDER BY id;")
        if table.count != 2
            throw Error("expected 2 rows, got " table.count)
        if table.rows[1].id != "a'b" || table.rows[1].n != 5 || table.rows[1].r != 2.5 || table.rows[1].body != "hello ' world"
            throw Error("row[1] values wrong: " table.rows[1].id "/" table.rows[1].n "/" table.rows[1].r "/" table.rows[1].body)
        if table[2, "id"] != "c" || table.rows[2]["n"] != -3
            throw Error("bracket access wrong: " table[2, "id"] "/" table.rows[2]["n"])
    }

    Query_BindsNullExplicitly() {
        db := SQLite(":memory:")
        db.Query("CREATE TABLE n_test (id TEXT PRIMARY KEY, parent TEXT);")
        db.Query("INSERT INTO n_test (id, parent) VALUES(?, ?);", "m1", SQLite.Null)
        db.Query("INSERT INTO n_test (id, parent) VALUES(?, ?);", "m2", "")
        nullRows := db.Query("SELECT id FROM n_test WHERE parent IS NULL;")
        emptyRows := db.Query("SELECT id FROM n_test WHERE parent = '';")
        if nullRows.count != 1 || nullRows.rows[1].id != "m1"
            throw Error("NULL binding wrong: count=" nullRows.count)
        if emptyRows.count != 1 || emptyRows.rows[1].id != "m2"
            throw Error("empty-string binding wrong: count=" emptyRows.count)
    }

    Query_CraftedValueCannotInject() {
        db := SQLite(":memory:")
        db.Query("CREATE TABLE inj_test (id TEXT PRIMARY KEY);")
        db.Query("INSERT INTO inj_test (id) VALUES(?);", "x' OR '1'='1")
        db.Query("INSERT INTO inj_test (id) VALUES(?);", "safe")
        rows := db.Query("SELECT id FROM inj_test WHERE id = ?;", "x' OR '1'='1")
        if rows.count != 1 || rows.rows[1].id != "x' OR '1'='1"
            throw Error("crafted value must match literally, got count=" rows.count)
        all := db.Query("SELECT COUNT(*) AS c FROM inj_test;")
        if all.rows[1].c != 2
            throw Error("expected 2 rows total, got " all.rows[1].c)
    }

    Query_DmlReturnsZero() {
        db := SQLite(":memory:")
        db.Query("CREATE TABLE d_test (id TEXT PRIMARY KEY, v INTEGER);")
        res := db.Query("INSERT INTO d_test (id, v) VALUES(?, ?);", "a", 1)
        if res != 0
            throw Error("INSERT should return 0, got " res)
        res := db.Query("UPDATE d_test SET v = ? WHERE id = ?;", 9, "a")
        if res != 0
            throw Error("UPDATE should return 0, got " res)
        row := db.Query("SELECT v FROM d_test WHERE id = ?;", "a")
        if row.rows[1].v != 9
            throw Error("updated value wrong: " row.rows[1].v)
    }
}
