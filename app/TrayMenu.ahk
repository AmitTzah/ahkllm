; ======================================================
; TrayMenu.ahk - tray menu lifecycle
;
; The tray menu is rebuilt from the current trayMenuItems global whenever
; settings change, so Menu Items edits (add/remove/rename) take effect live
; instead of after a restart (bug #37). Safe to call at startup and from
; Main's settings-updated hook chain.
; ======================================================

_rebuildTrayMenu() {
    global trayMenuItems
    A_TrayMenu.Delete()
    A_TrayMenu.Add("📋 Open Chat Window", (*) => openChatWindow())
    A_TrayMenu.Add("📝 New Chat", (*) => openChatWindow(ChatDB.Thread_Create()))
    A_TrayMenu.Add()
    for _, item in trayMenuItems {
        switch item.action {
            case "reload": A_TrayMenu.Add(item.menuText, (*) => Reload())
            case "exit":   A_TrayMenu.Add(item.menuText, (*) => ExitApp())
        }
    }
}
