; ======================================================
; ChatIconResolver.ahk — Resolve configured icon paths
;
; Settings store icon paths in two forms:
;   - repo-relative ("icons\IconOn.ico") — resolved against the repo root
;   - absolute ("C:\path\to\custom.ico", "\\server\share\x.ico") — used as-is
;
; ChatWindow.ahk lives in chat\, one level below the repo root, so relative
; paths need A_ScriptDir "\..\" as a prefix. Prefixing an absolute path with
; that mangles it ("chat\..\C:\..."), LoadPicture fails, and the chat window
; keeps its default icon. This resolver picks the correct form.
; ======================================================

ResolveIconPath(iconPath) {
    if iconPath = ""
        return ""
    ; Absolute forms: a drive letter ("C:\..." / "C:..."), a rooted path
    ; ("\..." or "/..."), or a UNC share (which also starts with "\").
    if RegExMatch(iconPath, "^(?:[A-Za-z]:|\\|/)")
        return iconPath
    return A_ScriptDir "\..\" iconPath
}
