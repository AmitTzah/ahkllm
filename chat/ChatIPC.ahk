; ======================================================
; ChatIPC.ahk — Minimal IPC for the persistent chat window
;
; The single-window ChatWindow no longer uses WM_ messages.
; All thread switching is done via HostObject callbacks.
; This file only provides postWebMessageFn needed by ChatUtils.
; ======================================================

class ChatIPCHandler {
    static responseWindow := unset
    static postWebMessageFn := unset
}