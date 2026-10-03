#Include ApplicationRepo.ahk
#Include ApplicationProcess.ahk
#Include ..\ThreadSettings.ahk

class ExternalApplications {
    static ProfilesPath() => AppInfo.DataDir "\applications.json"

    static Profiles() {
        profiles := FileExist(this.ProfilesPath()) ? jsongo.Parse(FileRead(this.ProfilesPath(), "UTF-8")) : Map()
        if !(profiles is Map)
            throw Error("The saved applications configuration must be an object.")
        return profiles
    }

    static Register(profile, confirm := true) {
        id := profile.Get("id", "")
        if !RegExMatch(id, "^[a-z0-9][a-z0-9._-]{0,79}$") || !profile.Has("command") || !(profile["command"] is Array) || !profile["command"].Length || Trim(profile["command"][1]) = ""
            throw Error("Invalid application connection profile.")
        for argument in profile["command"]
            if Type(argument) != "String" || InStr(argument, "`n") || InStr(argument, "`r")
                throw Error("Application command arguments must be single-line strings.")
        if profile.Get("working_directory", "") != "" && !DirExist(profile["working_directory"])
            throw Error("The application's working folder does not exist.")
        timeout := profile.Get("timeout_seconds", 60)
        if !IsInteger(timeout) || timeout < 1 || timeout > 300
            throw Error("Application timeout must be a whole number from 1 to 300 seconds.")
        profiles := this.Profiles()
        if profiles.Has(id) && jsongo.Stringify(profiles[id]) = jsongo.Stringify(profile)
            return id
        this.RequireIdle(id)
        if confirm {
            commandText := ""
            for argument in profile["command"]
                commandText .= argument " "
            if MsgBox("Connect application " profile.Get("name", id) "?`n`nIts configured program can run local operations:`n" commandText, "Connect application", "YesNo Icon?") != "Yes"
                throw Error("Application registration was cancelled.")
        }
        profiles[id] := profile
        this.SaveProfiles(profiles)
        return id
    }

    static SaveProfiles(profiles) {
        DirCreate(AppInfo.DataDir)
        temporary := this.ProfilesPath() "." ChatDB._UUID() ".tmp"
        FileOpen(temporary, "w", "UTF-8-RAW").Write(jsongo.Stringify(profiles))
        FileMove(temporary, this.ProfilesPath(), true)
    }

    static RequireIdle(applicationId) {
        for threadId, context in ApplicationChat.active {
            session := ApplicationRepo.Session(threadId)
            if session && session.application_id = applicationId
                throw Error("Wait for this application's running tasks before changing its connection.")
        }
    }

    static Disconnect(applicationId) {
        this.RequireIdle(applicationId)
        profiles := this.Profiles()
        if profiles.Has(applicationId) {
            profiles.Delete(applicationId)
            this.SaveProfiles(profiles)
        }
    }

    static Call(threadId, method, state, extra := "") {
        session := ApplicationRepo.Session(threadId)
        profiles := this.Profiles()
        if !session || !profiles.Has(session.application_id)
            throw Error("This application's connection is unavailable. Reconnect it to resume tools; chat history remains readable.")
        params := Map("state", state)
        if IsObject(extra)
            for key, value in extra
                params[key] := value
        return ApplicationProcess.Call(profiles[session.application_id], method, params)
    }

    static Import(package) {
        if package.Get("protocol", "") != "ahkllm.external-applications" || package.Get("version", 0) != 1
            throw Error("Unsupported external-session package.")
        applicationId := package.Get("application_id", "")
        if !this.Profiles().Has(applicationId)
            throw Error("Register this application connection before opening its session.")
        existing := ChatDB.db.Query("SELECT thread_id FROM application_sessions WHERE request_id=?;", package["request_id"])
        if existing.count
            return existing[1, "thread_id"]
        ChatDB.BeginTransaction()
        try {
            threadId := ChatDB.Thread_Create(package.Get("title", "Application session"))
            this.InitializeNewThreadSettings(threadId)
            ChatDB.db.Query("UPDATE chat_threads SET system_override=?, system_override_set=1 WHERE id=?;", package.Get("instructions", ""), threadId)
            awaiting := package.Get("await_first_message", false)
            ChatDB.db.Query("INSERT INTO application_sessions(thread_id,application_id,initial_state,request_id,initial_input) VALUES(?,?,?,?,?);", threadId, applicationId, jsongo.Stringify(package["state"]), package["request_id"], awaiting ? package.Get("initial_input", "") : "")
            if !awaiting {
                messageId := ChatDB.Msg_Insert({thread_id: threadId, role: "user", content: package.Get("message", "Begin task")})
                replay := [Map("role", "user", "content", ApplicationWire.InputParts(package.Get("initial_input", package.Get("message", "Begin task"))))]
                ApplicationRepo.SaveNode(messageId, package["state"], replay)
            }
            ChatDB.CommitTransaction()
            ChatDB._MarkPersistentDataChanged()
            return threadId
        } catch Error as e {
            ChatDB.RollbackTransaction()
            throw e
        }
    }

    static InitializeNewThreadSettings(threadId) {
        global responseWindowFontSize
        selection := ThreadSettings.NewChatSelection()
        settings := {modelOverride: selection.model, assistantId: selection.assistant ? selection.assistant.id : ""}
        if IsSet(responseWindowFontSize) && responseWindowFontSize
            settings.fontSize := responseWindowFontSize
        ChatDB.Thread_UpdateSettings(threadId, settings)
    }

    static FlushReleases() {
        profiles := this.Profiles()
        rows := ChatDB.db.Query("SELECT * FROM application_release_queue LIMIT 1;")
        for row in rows.rows {
            if !profiles.Has(row.application_id)
                continue
            try {
                result := ApplicationProcess.Call(profiles[row.application_id], "session.release", Map("state", jsongo.Parse(row.state_json)))
                if result.Get("released", false)
                    ChatDB.db.Query("DELETE FROM application_release_queue WHERE application_id=? AND state_json=?;", row.application_id, row.state_json)
            }
        }
    }

    static ForkState(threadId) {
        path := ChatDB.Msg_GetActivePath(threadId)
        if !path.Length || !ApplicationRepo.Session(threadId)
            return
        original := ApplicationRepo.State(threadId, path)
        result := this.Call(threadId, "session.fork", original)
        leaf := path[path.Length].id
        row := ChatDB.db.Query("SELECT replay_json,kind FROM application_nodes WHERE message_id=?;", leaf)
        if row.count
            ChatDB.db.Query("UPDATE application_nodes SET state_json=? WHERE message_id=?;", jsongo.Stringify(result["state"]), leaf)
        else
            ApplicationRepo.SaveNode(leaf, result["state"])
    }
}
