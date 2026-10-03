class ApplicationSessionReceiver {
    static openThread := ""

    static Register(callback) {
        this.openThread := callback
        OnMessage(0x4A, this.Receive.Bind(this))
    }

    static Receive(wParam, lParam, *) {
        if NumGet(lParam, 0, "UPtr") != 0x41484B41
            return 0
        size := NumGet(lParam, A_PtrSize, "UInt")
        if size < 2 || size > 32768 || Mod(size, 2)
            return 0
        packagePath := StrGet(NumGet(lParam, A_PtrSize * 2, "Ptr"), size // 2, "UTF-16")
        try {
            package := jsongo.Parse(FileRead(packagePath, "UTF-8"))
            threadId := ExternalApplications.Import(package)
            SetTimer(this.openThread.Bind(threadId), -10)
            return 1
        } catch Error as e {
            debugLog("[APPLICATION] Cannot open external session: " e.Message)
            return 0
        }
    }
}
