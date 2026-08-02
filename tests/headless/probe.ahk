; probe.ahk — Win32-level helper for the headless harness.
; Usage: AutoHotkey64.exe probe.ahk <command> <outFile> [arg1 ...]
; Writes a small JSON object to <outFile> and exits 0.
#Requires AutoHotkey v2.0.18+
#SingleInstance Off
#NoTrayIcon
DetectHiddenWindows true

command := A_Args.Length > 0 ? A_Args[1] : ""
outFile := A_Args.Length > 1 ? A_Args[2] : ""

; Never block the harness: log any error and force-exit.
OnError((err, mode) => (Write(Map("error", err.Message)), ExitApp(1)), -1)
SetTimer(ExitWatchdog, -15000)
ExitWatchdog(*) {
    Write(Map("error", "WATCHDOG fired"))
    ExitApp(1)
}

Write(obj) {
    global outFile
    if !outFile
        return
    lines := []
    for k, v in obj
        lines.Push(k "|" v)
    try FileAppend(Join("`n", lines), outFile, "UTF-8")
}

Join(sep, arr) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") v
    return out
}

ChatHwnd() {
    ; AHK v2 GUI windows have class "AutoHotkeyGUI" (the "AutoHotkey" class is
    ; the hidden script window). Find the ChatWindow process via its script
    ; window, then return its GUI window ("LLM AutoHotkey Assistant" while
    ; prewarmed, "Chat" / "Chat — <title>" after being shown/renamed).
    chatPid := 0
    for h in WinGetList("ahk_class AutoHotkey") {
        t := WinGetTitle("ahk_id " h)
        if InStr(t, "ChatWindow.ahk") {
            chatPid := WinGetPID("ahk_id " h)
            break
        }
    }
    if !chatPid
        return 0
    for h in WinGetList("ahk_pid " chatPid) {
        if WinGetClass("ahk_id " h) != "AutoHotkeyGUI"
            continue
        t := WinGetTitle("ahk_id " h)
        if (t = "LLM AutoHotkey Assistant") || (SubStr(t, 1, 4) = "Chat")
            return h
    }
    return 0
}

; Render an HICON into a 32x32 BGRA DIB and return its bytes as hex. Two
; LoadPicture calls for the same file return different handles, so handle
; equality cannot prove two icons are the same image — rendered bytes can.
IconFingerprint(hIcon) {
    if !hIcon
        return ""
    w := 32, h := 32
    bi := Buffer(40)  ; BITMAPINFOHEADER
    NumPut("uint", 40, bi, 0)
    NumPut("int", w, bi, 4)
    NumPut("int", -h, bi, 8)    ; negative height = top-down
    NumPut("ushort", 1, bi, 12)
    NumPut("ushort", 32, bi, 14)
    hdcScreen := DllCall("user32.dll\GetDC", "ptr", 0, "ptr")
    hdcMem := DllCall("gdi32.dll\CreateCompatibleDC", "ptr", hdcScreen, "ptr")
    bits := 0
    hbm := DllCall("gdi32.dll\CreateDIBSection", "ptr", hdcMem, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    if !hbm {
        DllCall("gdi32.dll\DeleteDC", "ptr", hdcMem)
        DllCall("user32.dll\ReleaseDC", "ptr", 0, "ptr", hdcScreen)
        return ""
    }
    old := DllCall("gdi32.dll\SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
    ; DI_NORMAL = 3
    DllCall("user32.dll\DrawIconEx", "ptr", hdcMem, "int", 0, "int", 0, "ptr", hIcon, "int", w, "int", h, "uint", 0, "ptr", 0, "uint", 3)
    byteCount := w * h * 4
    buf := Buffer(byteCount)
    DllCall("ntdll.dll\RtlMoveMemory", "ptr", buf, "ptr", bits, "uptr", byteCount)
    hex := ""
    loop byteCount
        hex .= Format("{:02X}", NumGet(buf, A_Index - 1, "uchar"))
    DllCall("gdi32.dll\SelectObject", "ptr", hdcMem, "ptr", old)
    DllCall("gdi32.dll\DeleteObject", "ptr", hbm)
    DllCall("gdi32.dll\DeleteDC", "ptr", hdcMem)
    DllCall("user32.dll\ReleaseDC", "ptr", 0, "ptr", hdcScreen)
    return hex
}

switch command {
    case "preflight":
        running := WinExist("Main.ahk ahk_class AutoHotkey") || WinExist("ChatWindow.ahk ahk_class AutoHotkey")
        Write(Map("running", running ? 1 : 0))

    case "kill-chat":
        hwnd := WinExist("ChatWindow.ahk ahk_class AutoHotkey")
        if hwnd
            WinClose("ahk_id " hwnd)
        Write(Map("closed", hwnd ? 1 : 0))

    case "chat-info":
        hwnd := ChatHwnd()
        title := hwnd ? WinGetTitle("ahk_id " hwnd) : ""
        chatWin := WinExist("Chat ahk_exe AutoHotkey64.exe") ? 1 : 0
        x := "", y := "", w := "", h := ""
        childClass := ""
        if hwnd {
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            child := DllCall("user32.dll\GetWindow", "ptr", hwnd, "uint", 5)  ; GW_CHILD
            if child {
                buf := Buffer(256)
                DllCall("user32.dll\GetClassName", "ptr", child, "ptr", buf, "int", 256)
                childClass := StrGet(buf)
            }
        }
        Write(Map("hwnd", hwnd ? hwnd : 0, "title", title, "chatWinExist", chatWin, "w", w, "h", h, "childClass", childClass))

    case "active-window":
        a := WinActive("A")
        t := a ? WinGetTitle("ahk_id " a) : ""
        Write(Map("active", a ? a : 0, "title", t))

    case "list-windows":
        parts := []
        for h in WinGetList("ahk_class AutoHotkey") {
            t := WinGetTitle("ahk_id " h)
            pid := WinGetPID("ahk_id " h)
            parts.Push("script: " SubStr(t, 1, 50) " pid=" pid)
            ; All top-level windows of that process (any class)
            for w in WinGetList("ahk_pid " pid) {
                wt := WinGetTitle("ahk_id " w)
                wc := WinGetClass("ahk_id " w)
                parts.Push("   win: class=" wc " title=" SubStr(wt, 1, 50) " vis=" DllCall("user32.dll\IsWindowVisible", "ptr", w))
            }
        }
        Write(Map("count", parts.Length, "windows", Join("; ", parts)))

    case "show-chat":
        hwnd := ChatHwnd()
        if hwnd {
            WinShow("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
        }
        Write(Map("shown", hwnd ? 1 : 0))

    case "icon-check":
        iconPath := A_Args[3]
        hwnd := ChatHwnd()
        hBig := 0
        hSmall := 0
        if hwnd {
            ; NOTE: read the SendMessage return value directly — referencing the
            ; built-in ErrorLevel hangs AutoHotkey64.exe at load in this environment.
            ; The Control parameter must be OMITTED ("" means "target control" and
            ; fails with 'Target control not found' on window-level messages).
            hBig := SendMessage(0x7F, 0, 0, , "ahk_id " hwnd)    ; WM_GETICON ICON_BIG
            hSmall := SendMessage(0x7F, 1, 0, , "ahk_id " hwnd)  ; WM_GETICON ICON_SMALL
        }
        hCustom := 0
        if iconPath && FileExist(iconPath) {
            try hCustom := LoadPicture(iconPath, "Icon1 w32 h32", &imgT)
        }
        ; The OLD buggy path (ChatWindow.ahk prefixed every icon path with
        ; A_ScriptDir "\..\"); it must still fail to load — the fixed code
        ; resolves absolute paths without that prefix.
        scriptDir := A_ScriptDir "\..\..\chat"
        hMangled := 0
        try hMangled := LoadPicture(scriptDir "\..\" iconPath, "Icon1 w32 h32", &imgT2)
        Write(Map(
            "hwnd", hwnd ? hwnd : 0,
            "hBig", hBig, "hSmall", hSmall,
            "hCustom", hCustom,
            "hMangled", hMangled,
            ; Handle equality is unreliable (same file loaded twice gives two
            ; handles), so compare rendered pixels instead.
            "customApplied", (IconFingerprint(hBig) = IconFingerprint(hCustom) || IconFingerprint(hSmall) = IconFingerprint(hCustom)) ? 1 : 0,
            "mangledLoaded", hMangled ? 1 : 0
        ))

    case "menu-open":
        Send("``")
        Sleep 400
        open := WinExist("ahk_class #32768") ? 1 : 0
        if open
            Send("{Esc}")
        Write(Map("open", open))

    case "close-test":
        hwnd := ChatHwnd()
        keys := A_Args.Length > 3 ? A_Args[3] : "^w"
        if hwnd {
            WinShow("ahk_id " hwnd)
            WinActivate("ahk_id " hwnd)
            Sleep 200
            Send(keys)
            Sleep 400
        }
        visible := hwnd ? DllCall("user32.dll\IsWindowVisible", "ptr", hwnd) : -1
        Write(Map("hwnd", hwnd ? hwnd : 0, "keys", keys, "visibleAfterKeys", visible))

    case "suspend-banner":
        ; Send the suspend hotkey combo (CapsLock & `)
        Send("{CapsLock Down}``{CapsLock Up}")
        Sleep 600
        text := ""
        found := 0
        ; The banner GUI has class AutoHotkeyGUI (like all AHK v2 GUIs).
        for h in WinGetList("ahk_class AutoHotkeyGUI") {
            t := WinGetText("ahk_id " h)
            if t && t != "" {
                text := t
                found := h
                break
            }
        }
        ; Toggle back off
        Send("{CapsLock Down}``{CapsLock Up}")
        Write(Map("found", found ? 1 : 0, "bannerText", text))

    case "input-window-pos":
        title := A_Args[3]
        hwnd := WinExist(title " ahk_class AutoHotkeyGUI")
        x := "", y := "", w := "", h := ""
        if hwnd {
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
        }
        Write(Map("hwnd", hwnd ? hwnd : 0, "x", x, "y", y, "w", w, "h", h))

    case "input-window-edit-color":
        ; Sample a pixel inside the input window's Edit field (rendered, not
        ; style-derived) so a regression like "dark window + light font renders
        ; invisible text on the Edit's default white background" is caught.
        title := A_Args[3]
        hwnd := WinExist(title " ahk_class AutoHotkeyGUI")
        if !hwnd {
            Write(Map("hwnd", 0, "color", ""))
            return
        }
        ; The Edit is the first control; sample its center via PrintWindow.
        RECT := Buffer(16)
        DllCall("user32.dll\GetClientRect", "ptr", hwnd, "ptr", RECT)
        cw := NumGet(RECT, 8, "int"), ch := NumGet(RECT, 12, "int")
        hdcScreen := DllCall("user32.dll\GetDC", "ptr", 0, "ptr")
        hdcMem := DllCall("gdi32.dll\CreateCompatibleDC", "ptr", hdcScreen, "ptr")
        hbm := DllCall("gdi32.dll\CreateCompatibleBitmap", "ptr", hdcScreen, "int", cw, "int", ch, "ptr")
        DllCall("gdi32.dll\SelectObject", "ptr", hdcMem, "ptr", hbm)
        DllCall("user32.dll\PrintWindow", "ptr", hwnd, "ptr", hdcMem, "uint", 2)
        ; Edit starts at x20 y+5 and spans most of the window width.
        sx := 20 + (cw - 40) // 2
        sy := 5 + (ch - 40) // 2
        color := DllCall("gdi32.dll\GetPixel", "ptr", hdcMem, "int", sx, "int", sy, "uint")
        DllCall("gdi32.dll\DeleteObject", "ptr", hbm)
        DllCall("gdi32.dll\DeleteDC", "ptr", hdcMem)
        DllCall("user32.dll\ReleaseDC", "ptr", 0, "ptr", hdcScreen)
        Write(Map("hwnd", hwnd, "color", Format("0x{:06X}", color & 0xFFFFFF), "sample", sx "," sy))

    case "send-menu-usage":
        ; Open backtick menu, navigate Quick Access (q) -> 7 (Usage Dashboard)
        Send("``")
        Sleep 350
        menuOpened := WinExist("ahk_class #32768") ? 1 : 0
        if menuOpened {
            Send("q")
            Sleep 300
            Send("7")
            Sleep 600
            Send("{Esc}")
        }
        Write(Map("menuOpened", menuOpened))

    case "open-input":
        ; Open the backtick menu and press the given accelerator key
        Send("``")
        Sleep 350
        menuOpened := WinExist("ahk_class #32768") ? 1 : 0
        Send(A_Args[3])
        Sleep 500
        Write(Map("done", 1, "menuOpened", menuOpened))

    case "close-input":
        Send("{Esc}")
        Sleep 200
        Write(Map("done", 1))

    default:
        Write(Map("error", "unknown command: " command))
}

ExitApp(0)
