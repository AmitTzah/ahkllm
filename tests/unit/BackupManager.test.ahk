; ======================================================
; BackupManager.test.ahk - generation/lifecycle coverage
;
; Archive I/O is isolated behind the manager's two validation/build methods so
; these tests exercise the state machine without creating real ZIPs.
; ======================================================

class BackupManagerTestDouble extends BackupManager {
    __New() {
        super.__New()
        this.buildCalls := 0
        this.failBuild := false
        this.markDuringBuild := false
    }

    _ValidateDestination() {
    }

    _CreateAndPublishBackup() {
        this.buildCalls += 1
        if this.markDuringBuild
            this.MarkDirty()
        if this.failBuild
            throw Error("test archive failure")
    }
}

class BackupCaptureTestDouble extends BackupManager {
    __New() {
        super.__New()
        this.attachmentId := ""
        this.mutationBlocked := false
    }

    ; Runs while _CaptureConsistentData still owns the coordination lock.
    _SnapshotDatabase(targetPath) {
        super._SnapshotDatabase(targetPath)
        try {
            AttachmentRepo.DeleteOne(this.attachmentId)
        } catch Error {
            this.mutationBlocked := true
        }
    }
}

class BackupManagerTest {
    static __New() {
        RegisterTestClass("BackupManagerTest")
    }

    DisabledTickDoesNothing() {
        manager := BackupManagerTestDouble()
        manager._folder := A_Temp
        manager.Tick()
        if manager.buildCalls != 0
            throw Error("disabled automatic backup must not build an archive")
    }

    CleanTickDoesNothing() {
        manager := BackupManagerTestDouble()
        manager._enabled := true
        manager._folder := A_Temp
        manager.Tick()
        if manager.buildCalls != 0
            throw Error("clean automatic backup must not build an archive")
    }

    DirtyTickBacksUpCapturedGeneration() {
        manager := BackupManagerTestDouble()
        manager._enabled := true
        manager._folder := A_Temp
        manager.MarkDirty()
        manager.Tick()
        if manager.buildCalls != 1
            throw Error("dirty automatic backup should build exactly once")
        if manager._changeGeneration != manager._backedUpGeneration
            throw Error("successful backup should clear the captured generation")
    }

    FailedBackupRemainsDirty() {
        manager := BackupManagerTestDouble()
        manager._enabled := true
        manager._folder := A_Temp
        manager.failBuild := true
        manager.MarkDirty()
        if manager.BackupNow()
            throw Error("failed backup should return false")
        if manager._changeGeneration = manager._backedUpGeneration
            throw Error("failed backup must remain pending")
        if !InStr(manager._lastError, "test archive failure")
            throw Error("failed backup should retain a useful error")
    }

    ManualBackupWorksWhenClean() {
        manager := BackupManagerTestDouble()
        manager._folder := A_Temp
        if !manager.BackupNow()
            throw Error("manual backup should run while clean")
        if manager.buildCalls != 1
            throw Error("manual backup should use the normal build implementation")
    }

    ManualBackupAppliesMapConfig() {
        manager := BackupManagerTestDouble()
        config := Map("enabled", true, "folder", A_Temp)
        if !manager.BackupNow(false, config)
            throw Error("manual backup with a Map config should succeed")
        if !manager._enabled || manager._folder != A_Temp
            throw Error("manual backup did not apply its supplied configuration")
    }

    EnabledWithoutFolderReportsRequiredStatus() {
        manager := BackupManager()
        manager._enabled := true
        status := manager.GetStatus()
        if status.text != "Backup folder required"
            throw Error("enabled backup with no folder must report a configuration requirement")
    }

    ManualBackupWithoutFolderReturnsActionableError() {
        manager := BackupManager()
        if manager.BackupNow(false, Map("enabled", true, "folder", ""))
            throw Error("manual backup with an empty folder must fail")
        if !InStr(manager._lastError, "choose a backup destination folder first")
            throw Error("empty-folder backup error is not actionable: " manager._lastError)
    }

    BackupConfigChangeClearsStaleError() {
        manager := BackupManager()
        manager._lastError := "old destination error"
        manager.ApplySettings(Map("backup", Map("enabled", true, "folder", A_Temp)))
        if manager._lastError != ""
            throw Error("changing backup configuration must clear a stale error")
    }

    ChangesDuringBackupRemainPending() {
        manager := BackupManagerTestDouble()
        manager._folder := A_Temp
        manager.MarkDirty()
        manager.markDuringBuild := true
        if !manager.BackupNow()
            throw Error("backup with an in-flight mutation should still succeed")
        if manager._changeGeneration = manager._backedUpGeneration
            throw Error("a change during backup must remain pending")
    }

    RunningStatusIsDistinctFromQueuedPending() {
        manager := BackupManagerTestDouble()
        manager._folder := A_Temp
        manager.MarkDirty()
        if manager.GetStatus().text != "Backup pending"
            throw Error("dirty but idle backup should report queued pending state")
        manager._running := true
        if manager.GetStatus().text != "Backing up..."
            throw Error("active backup should report that it is running, not merely pending")
    }

    ConcurrentBackupIsRejected() {
        manager := BackupManagerTestDouble()
        manager._folder := A_Temp
        manager._running := true
        if manager.BackupNow()
            throw Error("a concurrent backup must be rejected")
        if manager.buildCalls != 0
            throw Error("concurrent backup must not start a second build")
    }

    StaleArtifactsAreHandledConservatively() {
        folder := A_Temp "\\backup-manager-stale-" A_TickCount
        DirCreate(folder)
        finalPath := folder "\\" BackupManager.FinalName
        oldPath := folder "\\" BackupManager.OldName
        tmpPath := folder "\\" BackupManager.TempName
        FileAppend("known good", oldPath)
        FileAppend("interrupted", tmpPath)
        manager := BackupManagerTestDouble()
        manager._folder := folder
        manager._RecoverStaleTemp()
        try {
            if !FileExist(finalPath)
                throw Error("stale .old.zip should restore the previous good backup")
            if FileExist(oldPath) || FileExist(tmpPath)
                throw Error("stale backup artifacts should be cleaned after recovery")
        } finally {
            try DirDelete(folder, true)
        }
    }

    FailedReplacementRestoresPreviousGoodBackup() {
        folder := A_Temp "\\backup-manager-publish-failure-" A_TickCount
        DirCreate(folder)
        finalPath := folder "\\" BackupManager.FinalName
        tmpPath := folder "\\" BackupManager.TempName
        FileAppend("known good", finalPath)
        manager := BackupManagerTestDouble()
        manager._folder := folder
        try {
            try manager._PublishTemp(tmpPath)
            catch {
            }
            if !FileExist(finalPath)
                throw Error("failed replacement must leave the previous backup recoverable")
            if FileRead(finalPath) != "known good"
                throw Error("failed replacement corrupted the previous backup")
        } finally {
            try DirDelete(folder, true)
        }
    }

    SourceDataDestinationIsRejected() {
        manager := BackupManager()
        manager._folder := manager._SourceDataDir()
        try {
            manager._ValidateDestination()
        } catch {
            return
        }
        throw Error("the AHKLLM source data directory must not be a backup destination")
    }

    ParentDirectoryDestinationIsRejected() {
        manager := BackupManager()
        manager._folder := A_Temp "\\backup-parent-test\\..\\backup-target"
        try {
            manager._ValidateDestination()
        } catch Error as e {
            if InStr(e.Message, "parent-directory segments")
                return
            throw e
        }
        throw Error("backup destination with parent-directory segments must be rejected")
    }

    InitUsesStaticTimerInterval() {
        manager := BackupManagerTestDouble()
        manager._folder := ""
        try {
            manager.Init(Map("backup", Map("enabled", false, "folder", "")))
        } finally {
            manager.Shutdown()
        }
    }

    ExistingFileDestinationIsRejected() {
        filePath := A_Temp "\\backup-manager-destination-file-" A_TickCount ".txt"
        FileAppend("not a folder", filePath)
        manager := BackupManager()
        manager._folder := filePath
        try {
            manager._ValidateDestination()
        } catch Error as e {
            if InStr(e.Message, "is a file")
                return
            throw e
        } finally {
            try FileDelete(filePath)
        }
        throw Error("an existing file must not be accepted as a backup destination")
    }

    CaptureStagesEverySnapshotAttachmentBeforeMutationCanDeleteIt() {
        oldDataDir := AppInfo.DataDir
        oldSettingsPath := SettingsHandler.settingsPath
        root := A_Temp "\\backup-capture-" A_TickCount "-" Random(1000, 999999)
        stage := A_Temp "\\backup-stage-" A_TickCount "-" Random(1000, 999999)
        try {
            AppInfo.DataDir := root
            SettingsHandler.settingsPath := root "\\settings.json"
            DirCreate(root "\\attachments")
            FileAppend("required attachment", root "\\attachments\\required.txt")
            ChatDB.Close()
            ChatDB.Open(root "\\chat_history.db")
            threadId := ChatDB.Thread_Create("capture")
            msgId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: "references file"})
            attId := ChatDB.Attachment_Insert(msgId, {
                attachment_type: "text_file",
                file_path: "attachments\\required.txt",
                mime_type: "text/plain",
                original_filename: "required.txt",
                file_size: 19,
                extracted_text: ""
            })

            manager := BackupCaptureTestDouble()
            manager.attachmentId := attId
            DirCreate(stage)
            manager._CaptureConsistentData(stage)

            if !manager.mutationBlocked
                throw Error("destructive attachment mutation was not coordinated")
            if !FileExist(stage "\\attachments\\required.txt")
                throw Error("snapshot attachment was not staged")
            snapshot := SQLite(stage "\\chat_history.db")
            try {
                rows := snapshot.Query("SELECT file_path FROM message_attachments WHERE id=?;", attId)
                if rows.count != 1
                    throw Error("snapshot no longer references the attachment")
            } finally {
                snapshot.Close()
            }
            if !FileExist(root "\\attachments\\required.txt")
                throw Error("coordinated mutation deleted the live attachment")
        } finally {
            ChatDB.Close()
            AppInfo.DataDir := oldDataDir
            SettingsHandler.settingsPath := oldSettingsPath
            try DirDelete(root, true)
            try DirDelete(stage, true)
        }
    }
}
