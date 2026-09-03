; ======================================================
; BackupManager.ahk - local, replaceable user-data backups
;
; The manager lives in Main.ahk. ChatWindow and other processes notify Main
; when they commit durable data so the timer never has to scan the data tree.
; ======================================================

class BackupManager {
    static IntervalMs := 20 * 60 * 1000
    static FinalName := "AHKLLM Backup.zip"
    static TempName := "AHKLLM Backup.tmp.zip"
    static OldName := "AHKLLM Backup.old.zip"
    static StatusPath := A_Temp "\AhkLLM_Backup_Status.json"
    static CaptureMutexName := "Local\AHKLLM-Backup-Capture"
    static _captureDepth := 0

    __New() {
        this._enabled := false
        this._folder := ""
        this._changeGeneration := 0
        this._backedUpGeneration := 0
        this._running := false
        this._lastSuccessfulTime := ""
        this._lastError := ""
        this._initialized := false
        this._timerFn := this.Tick.Bind(this)
    }

    Init(settings := "") {
        if IsObject(settings)
            this.ApplySettings(settings)
        this._initialized := true
        this._RecoverStaleTemp()
        SetTimer(this._timerFn, BackupManager.IntervalMs)
        this.PublishStatus()
    }

    ApplySettings(settings := "") {
        global backupEnabled, backupFolder
        oldEnabled := this._enabled
        oldFolder := this._folder
        if IsObject(settings) && settings.Has("backup") {
            config := settings["backup"]
            if IsObject(config) {
                this._enabled := config.Has("enabled") ? this._ToBool(config["enabled"]) : false
                this._folder := config.Has("folder") ? Trim(config["folder"]) : ""
            } else {
                this._enabled := false
                this._folder := ""
            }
        } else {
            this._enabled := IsSet(backupEnabled) ? this._ToBool(backupEnabled) : false
            this._folder := IsSet(backupFolder) ? Trim(backupFolder) : ""
        }
        if this._enabled != oldEnabled || this._folder != oldFolder
            this._lastError := ""
        if this._initialized
            this._RecoverStaleTemp()
        this.PublishStatus()
    }

    ; Called only at authoritative persistence boundaries.
    MarkDirty() {
        this._changeGeneration += 1
        this.PublishStatus()
    }

    ; Cross-process entry point used by ChatDB when this process is ChatWindow.
    static MarkPersistentDataChanged() {
        global gBackupManager, requestParams
        if IsSet(gBackupManager) && IsObject(gBackupManager) {
            gBackupManager.MarkDirty()
            return
        }
        if IsSet(requestParams) && IsObject(requestParams) && requestParams.Has("mainScriptHiddenHwnd")
            CustomMessages.notifyBackupDirty(requestParams["mainScriptHiddenHwnd"])
    }

    Tick(*) {
        if !this._enabled || !this._folder
            return
        if this._changeGeneration <= this._backedUpGeneration || this._running
            return
        try this._ValidateDestination()
        catch Error as e {
            this._SetError("destination is unavailable: " e.Message)
            return
        }
        this.BackupNow(true)
    }

    ; Manual and automatic backups converge here. Tick enforces the automatic
    ; enabled/dirty gates; an explicit manual request can run while automatic
    ; backups are disabled.
    BackupNow(isAutomatic := false, manualConfig := "") {
        if this._running {
            if !isAutomatic
                this._SetError("another backup is already running")
            return false
        }
        if IsObject(manualConfig) {
            ; WM backup requests are decoded from JSON and may be jsongo
            ; objects rather than AHK Maps. Normalize before using Has().
            normalizedConfig := SettingsHandler._ToMap(manualConfig)
            this.ApplySettings(Map("backup", normalizedConfig))
        }
        try this._ValidateDestination()
        catch Error as e {
            this._SetError("destination is unavailable: " e.Message)
            return false
        }

        capturedGeneration := this._changeGeneration
        this._running := true
        this._lastError := ""
        this.PublishStatus()
        try {
            this._CreateAndPublishBackup()
            ; A notification queued by another process while the synchronous
            ; archive was running is processed after this returns. In either
            ; case, only the captured generation is cleared.
            this._backedUpGeneration := capturedGeneration
            this._lastSuccessfulTime := A_Now
            this._lastError := ""
            this.PublishStatus()
            return true
        } catch Error as e {
            this._SetError(e.Message)
            return false
        } finally {
            this._running := false
            this.PublishStatus()
        }
    }

    Shutdown(*) {
        if this._initialized
            SetTimer(this._timerFn, 0)
        this._initialized := false
        this._running := false
    }

    GetStatus() {
        text := "No backup has been created yet"
        if this._enabled && !this._folder
            text := "Backup folder required"
        else if this._lastError
            text := "Backup failed: " this._lastError
        else if this._running
            text := "Backing up..."
        else if this._changeGeneration > this._backedUpGeneration
            text := "Backup pending"
        else if this._lastSuccessfulTime
            text := "Last backup: " this._FormatTime(this._lastSuccessfulTime)
        else if this._folder {
            finalPath := this._folder "\" BackupManager.FinalName
            if FileExist(finalPath)
                text := "Last backup: " this._FormatTime(FileGetTime(finalPath, "M"))
        }
        return {
            enabled: this._enabled,
            folder: this._folder,
            text: text,
            lastBackupTime: this._lastSuccessfulTime,
            lastError: this._lastError,
            pending: this._changeGeneration > this._backedUpGeneration,
            running: this._running
        }
    }

    PublishStatus() {
        ; Status delivery is deliberately best-effort: a closed ChatWindow or
        ; a locked temp directory must never turn a successful backup into a
        ; failed backup.
        try {
            f := FileOpen(BackupManager.StatusPath, "w", "UTF-8")
            f.Write(jsongo.Stringify(this.GetStatus()))
            f.Close()
        } catch {
        }
        global chatWindowhWnd
        if IsSet(chatWindowhWnd) && chatWindowhWnd && WinExist("ahk_id " chatWindowhWnd)
            CustomMessages.notifyBackupStatus(chatWindowhWnd)
    }

    _CreateAndPublishBackup() {
        stage := A_Temp "\AhkLLM_Backup_" A_TickCount "_" Random(1000, 999999)
        tmpPath := this._folder "\" BackupManager.TempName
        try {
            this._PrepareTemp(tmpPath)
            DirCreate(stage)
            ; The DB and the files it references must be captured as one
            ; short, coordinated operation. Compression happens afterwards.
            this._CaptureConsistentData(stage)

            settingsPath := SettingsHandler.settingsPath
            if !settingsPath
                settingsPath := AppInfo.DataDir "\settings.json"
            if FileExist(settingsPath)
                FileCopy(settingsPath, stage "\settings.json", 1)
            dataRoot := this._SourceDataDir()
            systemMessagesPath := dataRoot "\system-messages"
            if DirExist(systemMessagesPath)
                DirCopy(systemMessagesPath, stage "\system-messages", true)

            this._CompressStage(stage, tmpPath)
            this._PublishTemp(tmpPath)
        } finally {
            try DirDelete(stage, true)
        }
    }

    _CaptureConsistentData(stage) {
        lockHandle := BackupManager.BeginCaptureCoordination()
        try {
            snapshotPath := stage "\chat_history.db"
            this._SnapshotDatabase(snapshotPath)
            this._CaptureAttachmentFiles(snapshotPath, stage)
        } finally {
            BackupManager.EndCaptureCoordination(lockHandle)
        }
    }

    ; Copy only the attachment paths visible in the SQLite snapshot. A live
    ; DirCopy would mix two different database/file generations.
    _CaptureAttachmentFiles(snapshotPath, stage) {
        snapshotDb := SQLite(snapshotPath)
        try {
            rows := snapshotDb.Query("SELECT DISTINCT file_path FROM message_attachments;")
            dataRoot := this._SourceDataDir()
            attachmentsRoot := dataRoot "\attachments"
            for row in rows.rows {
                relativePath := StrReplace(row.file_path, "/", "\")
                prefix := "attachments\"
                if StrLower(SubStr(relativePath, 1, StrLen(prefix))) != prefix
                    throw Error("attachment path is outside the attachments directory: " row.file_path)
                relativePath := SubStr(relativePath, StrLen(prefix) + 1)
                if !relativePath || InStr(relativePath, "..")
                    throw Error("invalid attachment path in database: " row.file_path)

                sourcePath := attachmentsRoot "\" relativePath
                targetPath := stage "\attachments\" relativePath
                if !FileExist(sourcePath)
                    throw Error("attachment referenced by database is missing: " row.file_path)
                targetDir := SubStr(targetPath, 1, InStr(targetPath, "\", , -1) - 1)
                if !DirExist(targetDir)
                    DirCreate(targetDir)
                FileCopy(sourcePath, targetPath, 1)
                if !FileExist(targetPath)
                    throw Error("attachment could not be staged: " row.file_path)
            }
        } finally {
            snapshotDb.Close()
        }
    }

    ; Cross-process coordination shared by Main and ChatWindow. The local
    ; depth guard also makes an attempted same-process re-entrant mutation
    ; fail instead of relying on Windows mutex recursion semantics.
    static BeginCaptureCoordination() {
        if this._captureDepth
            throw Error("backup capture coordination is already active")
        handle := DllCall("CreateMutexW", "ptr", 0, "int", false,
            "wstr", this.CaptureMutexName, "ptr")
        if !handle
            throw Error("could not create backup capture coordination mutex")
        waitResult := DllCall("WaitForSingleObject", "ptr", handle, "uint", 30000, "uint")
        if waitResult != 0 && waitResult != 0x80 {
            DllCall("CloseHandle", "ptr", handle)
            throw Error("timed out waiting for backup capture coordination")
        }
        this._captureDepth := 1
        return handle
    }

    static EndCaptureCoordination(handle) {
        if !handle
            return
        this._captureDepth := 0
        DllCall("ReleaseMutex", "ptr", handle)
        DllCall("CloseHandle", "ptr", handle)
    }

    ; Attachment mutation callers use this entry point. It is deliberately
    ; separate from BeginCaptureCoordination so same-process test hooks and
    ; accidental re-entrancy cannot acquire the recursive mutex.
    static BeginAttachmentMutation() {
        if this._captureDepth
            throw Error("attachment mutation blocked during backup capture")
        return this._BeginAttachmentMutation()
    }

    static _BeginAttachmentMutation() {
        handle := DllCall("CreateMutexW", "ptr", 0, "int", false,
            "wstr", this.CaptureMutexName, "ptr")
        if !handle
            throw Error("could not create backup capture coordination mutex")
        waitResult := DllCall("WaitForSingleObject", "ptr", handle, "uint", 30000, "uint")
        if waitResult != 0 && waitResult != 0x80 {
            DllCall("CloseHandle", "ptr", handle)
            throw Error("timed out waiting for backup capture coordination")
        }
        return handle
    }

    static EndAttachmentMutation(handle) => this._EndAttachmentMutation(handle)

    static _EndAttachmentMutation(handle) {
        if !handle
            return
        DllCall("ReleaseMutex", "ptr", handle)
        DllCall("CloseHandle", "ptr", handle)
    }

    _SnapshotDatabase(targetPath) {
        if !ChatDB.isOpen || !ChatDB.db.ptr
            throw Error("chat database is not available")
        if FileExist(targetPath)
            FileDelete(targetPath)

        openCode := SQLite3.open_v2(targetPath, &destinationPtr, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if openCode != SQLITE_OK {
            if destinationPtr
                SQLite3.close_v2(destinationPtr)
            throw Error("SQLite backup destination could not be opened: " SQLite3.errstr(openCode))
        }
        backupPtr := 0
        try {
            sourceName := Buffer(StrPut("main", "UTF-8"))
            StrPut("main", sourceName, "UTF-8")
            backupPtr := DllCall(SQLite3.bin "\sqlite3_backup_init", "ptr", destinationPtr,
                "ptr", sourceName, "ptr", ChatDB.db.ptr, "ptr", sourceName, "cdecl ptr")
            if !backupPtr
                throw Error("SQLite backup initialization failed: " SQLite3.errmsg(destinationPtr))

            loop 100 {
                rc := DllCall(SQLite3.bin "\sqlite3_backup_step", "ptr", backupPtr, "int", -1, "cdecl int")
                if rc = SQLITE_DONE
                    break
                if rc != SQLITE_OK && rc != SQLITE_BUSY && rc != SQLITE_LOCKED
                    throw Error("SQLite backup failed: " SQLite3.errstr(rc))
                if A_Index = 100
                    throw Error("SQLite backup timed out while the database was busy")
                Sleep 50
            }
            finishCode := DllCall(SQLite3.bin "\sqlite3_backup_finish", "ptr", backupPtr, "cdecl int")
            backupPtr := 0
            if finishCode != SQLITE_OK
                throw Error("SQLite backup finalization failed: " SQLite3.errstr(finishCode))
        } finally {
            if backupPtr
                DllCall(SQLite3.bin "\sqlite3_backup_finish", "ptr", backupPtr, "cdecl int")
            if destinationPtr
                SQLite3.close_v2(destinationPtr)
        }
    }

    _CompressStage(stage, tmpPath) {
        ; Compress-Archive is part of Windows PowerShell. Fastest keeps large
        ; attachment backups responsive while still producing a standard ZIP.
        ps := "$ErrorActionPreference = 'Stop'; Compress-Archive -Path " this._PsQuote(stage "\*") " -DestinationPath " this._PsQuote(tmpPath) " -CompressionLevel Fastest -Force"
        command := "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"" ps "`""
        exitCode := RunWait(command, , "Hide")
        if exitCode != 0 || !FileExist(tmpPath) || FileGetSize(tmpPath) <= 0
            throw Error("ZIP creation failed")
    }

    _PublishTemp(tmpPath) {
        finalPath := this._folder "\" BackupManager.FinalName
        oldPath := this._folder "\" BackupManager.OldName
        ; A crash can leave the previous good ZIP under .old.zip after the
        ; final-name move. Restore that artifact before starting a new
        ; replacement; never discard the only known-good copy.
        if FileExist(oldPath) {
            if !FileExist(finalPath)
                FileMove(oldPath, finalPath, 1)
            else
                FileDelete(oldPath)
        }

        try {
            hadPrevious := FileExist(finalPath)
            if hadPrevious {
                FileMove(finalPath, oldPath, 1)
                if FileExist(finalPath)
                    throw Error("could not stage the previous backup")
            }
            FileMove(tmpPath, finalPath, 1)
            if FileExist(tmpPath) || !FileExist(finalPath)
                throw Error("could not publish the new backup")
        } catch Error as e {
            ; Restore the known-good artifact if replacement failed. If the
            ; restore itself fails, the .old.zip remains available for manual
            ; recovery and is never treated as the current backup.
            if !FileExist(finalPath) && FileExist(oldPath) {
                try FileMove(oldPath, finalPath, 1)
            }
            throw e
        }
        if FileExist(oldPath)
            FileDelete(oldPath)
    }

    _PrepareTemp(tmpPath) {
        if FileExist(tmpPath)
            FileDelete(tmpPath)
        if FileExist(tmpPath)
            throw Error("stale temporary ZIP cannot be removed")
    }

    _RecoverStaleTemp() {
        if !this._folder
            return
        try {
            tmpPath := this._folder "\" BackupManager.TempName
            if FileExist(tmpPath)
                FileDelete(tmpPath)
            finalPath := this._folder "\" BackupManager.FinalName
            oldPath := this._folder "\" BackupManager.OldName
            if !FileExist(finalPath) && FileExist(oldPath)
                FileMove(oldPath, finalPath, 1)
            else if FileExist(finalPath) && FileExist(oldPath)
                FileDelete(oldPath)
        } catch {
        }
    }

    _ValidateDestination() {
        if !this._folder
            throw Error("choose a backup destination folder first")
        if RegExMatch(this._folder, "(^|[\\/])\.\.([\\/]|$)")
            throw Error("backup destination must not contain parent-directory segments")
        ; The Browse button uses FileSelect("D"), but the text field also allows
        ; manual entry/paste. Never treat an existing file as a directory.
        if FileExist(this._folder) && !DirExist(this._folder)
            throw Error("backup destination is a file; choose a folder")
        destinationRoot := StrLower(RTrim(this._folder, "\/"))
        sourceRoot := StrLower(RTrim(this._SourceDataDir(), "\/"))
        if destinationRoot = sourceRoot || InStr(destinationRoot, sourceRoot "\") = 1
            throw Error("destination cannot be inside the AHKLLM data folder")
        if !DirExist(this._folder)
            DirCreate(this._folder)
        if !DirExist(this._folder)
            throw Error("folder does not exist and could not be created")

        probePath := this._folder "\.ahkllm-backup-write-test-" A_TickCount
        try {
            f := FileOpen(probePath, "w")
            f.Write("test")
            f.Close()
            FileDelete(probePath)
        } catch Error as e {
            try FileDelete(probePath)
            throw Error("folder is not writable: " e.Message)
        }
    }

    _IsWithin(path, root) {
        path := StrLower(RTrim(path, "\\/"))
        root := StrLower(RTrim(root, "\\/"))
        return path = root || InStr(path, root "\\") = 1
    }

    ; The DB path is the authoritative data-root anchor. SettingsHandler's
    ; configured settings path is used so isolated profiles and tests cannot accidentally
    ; back up the developer's real AppData directory.
    _SourceDataDir() {
        if ChatDB.dbPath {
            slash := InStr(ChatDB.dbPath, "\", , -1)
            if slash > 1
                return SubStr(ChatDB.dbPath, 1, slash - 1)
        }
        return AppInfo.DataDir
    }

    _SetError(message) {
        this._lastError := message
        this.PublishStatus()
    }

    _FormatTime(value) {
        try {
            return FormatTime(value, "MMM d, yyyy HH:mm")
        } catch {
            return value
        }
    }

    _PsQuote(value) => "'" StrReplace(value, "'", "''") "'"

    _ToBool(value) => value = true || value = 1 || value = "1" || value = "true" || value = "on"
}
