; ======================================================
; ChatIconResolver.test.ahk — Regression tests for chat/ChatIconResolver.ahk
;
; Bug: ChatWindow.ahk built the window-icon path as A_ScriptDir "\..\" iconOn,
; which mangles absolute paths picked outside the repo ("chat\..\C:\..."),
; so LoadPicture fails and the chat window keeps its default icon. The resolver
; now returns absolute paths unchanged and prefixes only repo-relative paths.
; ======================================================

class ChatIconResolverTest {

    static __New() {
        RegisterTestClass("ChatIconResolverTest")
    }

    ; Repo-relative paths get the repo-root prefix (A_ScriptDir "\.." — in the
    ; test runner A_ScriptDir is tests\, so this points at the repo root).
    RelativePath_PrefixedWithRepoRoot() {
        repoRoot := A_ScriptDir "\.."
        resolved := ResolveIconPath("icons\IconOn.ico")
        if resolved != repoRoot "\icons\IconOn.ico"
            throw Error("Expected repo-root prefix, got: " resolved)
        if !FileExist(resolved)
            throw Error("Resolved relative path does not exist: " resolved)
    }

    ; Absolute drive-letter paths (the "picked outside the repo" case) must be
    ; returned unchanged instead of being prefixed.
    AbsoluteDrivePath_UsedAsIs() {
        absPath := "C:\Users\someone\AppData\Local\Temp\custom.ico"
        if ResolveIconPath(absPath) != absPath
            throw Error("Absolute drive path was modified: " ResolveIconPath(absPath))
    }

    ; Forward-slash drive paths are absolute too.
    AbsoluteForwardSlashPath_UsedAsIs() {
        absPath := "C:/Temp/custom.ico"
        if ResolveIconPath(absPath) != absPath
            throw Error("Absolute forward-slash path was modified: " ResolveIconPath(absPath))
    }

    ; UNC share paths must not get the repo-root prefix either.
    UncPath_UsedAsIs() {
        absPath := "\\server\share\custom.ico"
        if ResolveIconPath(absPath) != absPath
            throw Error("UNC path was modified: " ResolveIconPath(absPath))
    }

    ; Rooted paths (no drive letter) are absolute.
    RootedPath_UsedAsIs() {
        absPath := "\icons\custom.ico"
        if ResolveIconPath(absPath) != absPath
            throw Error("Rooted path was modified: " ResolveIconPath(absPath))
    }

    ; An empty value means "no icon" — never build a path from it.
    EmptyValue_ReturnsEmpty() {
        if ResolveIconPath("") != ""
            throw Error("Empty icon path should stay empty")
    }

    ; End-to-end: the repo's default icon must still load through the resolver
    ; (the bug's unconditional prefix made the absolute case fail to load).
    ResolvedRelativeIcon_LoadsPicture() {
        resolved := ResolveIconPath("icons\IconOn.ico")
        hIcon := 0
        try hIcon := LoadPicture(resolved, "Icon1 w32 h32", &imgType)
        if !hIcon
            throw Error("LoadPicture failed for resolved icon: " resolved)
    }
}
