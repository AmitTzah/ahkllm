_OpenExternalThreadWhenReady(threadId, started := 0) {
    global chatWindowhWnd, chatWindowPID
    if !started
        started := A_TickCount
    if !chatWindowhWnd && IsSet(chatWindowPID) && ProcessExist(chatWindowPID) && A_TickCount - started < 15000 {
        SetTimer(() => _OpenExternalThreadWhenReady(threadId, started), -100)
        return
    }
    openChatWindow(threadId, true)
}
ApplicationSessionReceiver.Register(_OpenExternalThreadWhenReady)
