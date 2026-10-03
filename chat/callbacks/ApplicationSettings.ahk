; Generic connection management exposed through Settings -> Applications.
postApplicationConnections(*) {
    connections := []
    for id, profile in ExternalApplications.Profiles() {
        count := ChatDB.db.Query("SELECT COUNT(*) AS count FROM application_sessions WHERE application_id=?;", id)
        connections.Push({id: id, name: profile.Get("name", id), command: profile["command"], working_directory: profile.Get("working_directory", ""), timeout_seconds: profile.Get("timeout_seconds", 60), chat_count: Integer(count[1, "count"])})
    }
    postWebMessage("applicationConnections", {connections: connections})
}

handleSaveApplicationConnection(parsed) {
    profile := parsed.Get("profile", "")
    if !(profile is Map)
        throw Error("Application connection must be an object.")
    ExternalApplications.Register(profile, false)
    postApplicationConnections()
    postApplicationState()
}

handleDisconnectApplicationConnection(parsed) {
    ExternalApplications.Disconnect(parsed.Get("id", ""))
    postApplicationConnections()
    postApplicationState()
}

handleBrowseApplicationProgram(*) {
    selected := FileSelect(3, , "Select application program", "Programs (*.exe; *.com; *.bat; *.cmd)")
    if selected != ""
        postWebMessage("applicationProgramSelected", {path: selected})
}
