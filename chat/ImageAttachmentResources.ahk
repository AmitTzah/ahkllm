; Serve authorized image attachments through intercepted local WebView streams.
; Static virtual-host mappings bypass WebResourceRequested, so use a separate host.
#Include ..\shared\ImageThumbnailCache.ahk

class ImageAttachmentResources {
    static PREFIX := "https://attachments.ahk.localhost/attachment-images/"

    static Initialize(window) {
        window.AddWebResourceRequestedFilter(ImageAttachmentResources.PREFIX "*", 0)
        window.WebResourceRequested((sender, args) => ImageAttachmentResources.HandleResource(sender, args))
    }

    static Metadata(attachment, threadId) {
        if !RegExMatch(threadId, "^[A-Za-z0-9_-]+$") || !RegExMatch(attachment.id, "^[A-Za-z0-9_-]+$")
            return { originalUrl: "", thumbnailUrl: "", key: "", width: 300, height: 300 }
        try descriptor := ImageThumbnailCache.Describe(attachment.file_path)
        catch
            descriptor := { key: "", cached: false, width: 300, height: 300 }
        base := ImageAttachmentResources.PREFIX threadId "/" attachment.id
        return { originalUrl: base "/original?v=" descriptor.key,
            thumbnailUrl: descriptor.cached ? base "/thumbnail?v=" descriptor.key : "",
            key: descriptor.key, width: descriptor.width, height: descriptor.height }
    }

    static AuthorizedAttachment(threadId, attachmentId) {
        if ThreadLockService.IsLocked(threadId) && !ThreadLockService.IsUnlockedInSession(threadId)
            throw Error("This chat is locked.")
        table := ChatDB.db.Query("SELECT a.id, a.file_path, a.mime_type, a.attachment_type FROM message_attachments a JOIN messages m ON m.id=a.message_id JOIN chat_threads t ON t.id=m.thread_id WHERE a.id=? AND m.thread_id=?;", attachmentId, threadId)
        if !table.rows.Length || table.rows[1].attachment_type != "image"
            throw Error("Image attachment is not available in this chat.")
        row := table.rows[1]
        ImageThumbnailCache.SourcePath(row.file_path)
        return row
    }

    static HandleResource(sender, args) {
        uri := args.Request.Uri
        if !RegExMatch(uri, "^https://attachments\.ahk\.localhost/attachment-images/([A-Za-z0-9_-]+)/([A-Za-z0-9_-]+)/(original|thumbnail)(?:\?.*)?$", &match)
            return
        try {
            attachment := ImageAttachmentResources.AuthorizedAttachment(match[1], match[2])
            descriptor := ImageThumbnailCache.Describe(attachment.file_path)
            path := match[3] = "thumbnail" ? descriptor.preview : descriptor.source
            if !FileExist(path)
                throw Error("Image file was not found.")
            pointer := 0
            status := DllCall("shlwapi\SHCreateStreamOnFileEx", "WStr", path, "UInt", 0x40,
                "UInt", 0, "Int", false, "Ptr", 0, "Ptr*", &pointer, "Int")
            if status != 0 || !pointer
                throw Error("Image stream could not be opened.")
            stream := WebView2.Stream()
            stream.Ptr := pointer
            mime := match[3] = "thumbnail" ? "image/webp" : attachment.mime_type
            if !RegExMatch(mime, "i)^image/(png|jpeg|gif|webp|bmp|tiff)$")
                mime := "application/octet-stream"
            args.Response := sender.Environment.CreateWebResourceResponse(stream, 200, "OK",
                "Content-Type: " mime "`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nAccess-Control-Allow-Origin: https://ahk.localhost")
        } catch Error as imageError {
            debugLog("[IMAGE RESOURCE] " imageError.Message)
            args.Response := sender.Environment.CreateWebResourceResponse(WebView2.CreateMemStream(), 403, "Unavailable", "Cache-Control: no-store`r`nAccess-Control-Allow-Origin: https://ahk.localhost")
        }
    }

    static SaveThumbnail(parsed) {
        attachment := ImageAttachmentResources.AuthorizedAttachment(parsed.Get("threadId", ""), parsed.Get("attachmentId", ""))
        ImageThumbnailCache.Save(attachment.file_path, parsed.Get("key", ""), parsed.Get("base64", ""),
            parsed.Get("width", 0), parsed.Get("height", 0))
    }
}
