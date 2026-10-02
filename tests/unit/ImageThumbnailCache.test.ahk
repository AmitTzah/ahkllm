class ImageThumbnailCacheTest {
    static __New() {
        RegisterTestClass("ImageThumbnailCacheTest")
    }

    Cache_MetadataRemainsSmallAndOriginalBytesRemainUnchanged() {
        oldRoot := AppInfo.DataDir
        directory := A_Temp "\test_image_cache_" A_TickCount "_" Random(1000,999999)
        AppInfo.DataDir := directory
        source := directory "\attachments\legacy.png"
        cached := ""
        try {
            DirCreate(directory "\attachments")
            bytes := Buffer(24,0)
            NumPut("UInt",0x474E5089,bytes,0)
            NumPut("UChar",0x10,bytes,18) ; width 4096, big endian
            NumPut("UChar",0x18,bytes,22) ; height 6144, big endian
            file := FileOpen(source,"w")
            file.RawWrite(bytes,bytes.Size)
            file.Length := 32 * 1024 * 1024
            file.Close()
            modified := FileGetTime(source,"M")
            started := A_TickCount
            descriptor := ImageThumbnailCache.Describe("attachments\legacy.png")
            if A_TickCount-started > 1000 || descriptor.width != 200 || descriptor.height != 300
                throw Error("Legacy image metadata should be obtained without decoding or encoding the full image")
            metadata := ImageAttachmentResources.Metadata({id:"image-1",file_path:"attachments\legacy.png"},"thread-1")
            if StrLen(jsongo.Stringify(metadata)) > 1024 || !InStr(metadata.originalUrl,"attachment-images/thread-1/image-1/original")
                throw Error("Browsing metadata must stay small regardless of original image size")
            webp := Buffer(12,0)
            NumPut("UInt",0x46464952,webp,0) ; RIFF
            NumPut("UInt",4,webp,4)
            NumPut("UInt",0x50424557,webp,8) ; WEBP
            cached := ImageThumbnailCache.Save("attachments\legacy.png",descriptor.key,ImageUtils._Base64Encode(webp),4096,6144)
            if !ImageThumbnailCache.Describe("attachments\legacy.png").cached
                throw Error("Cached preview must be reusable on reopening")
            if FileGetSize(source) != 32*1024*1024 || FileGetTime(source,"M") != modified
                throw Error("Thumbnail caching must never modify the original image")
            threw := false
            try ImageThumbnailCache.Save("attachments\legacy.png","stale-version",ImageUtils._Base64Encode(webp),4096,6144)
            catch
                threw := true
            if !threw
                throw Error("Stale thumbnail writes must be rejected")
        } finally {
            AppInfo.DataDir := oldRoot
            for path in [source,cached,cached != "" ? cached ".ini" : ""] {
                if path != ""
                    try FileDelete(path)
            }
            try DirDelete(directory "\image-thumbnails")
            try DirDelete(directory "\attachments")
            try DirDelete(directory)
        }
    }

    Cache_RejectsUnmanagedPathsAndNonImagePayloads() {
        for path in ["settings.json","attachments\..\settings.json","attachments\sub\image.png","C:\private.png"] {
            threw := false
            try ImageThumbnailCache.SourcePath(path)
            catch
                threw := true
            if !threw
                throw Error("Cache must reject paths outside direct managed attachments")
        }
    }

    Resources_RequireCorrectAttachmentOwnerAndUnlockedChat() {
        oldRoot := AppInfo.DataDir
        directory := A_Temp "\test_image_owner_profile_" A_TickCount "_" Random(1000,999999)
        AppInfo.DataDir := directory
        if ChatDB.isOpen
            ChatDB.Close()
        database := A_Temp "\test_image_owner_" A_TickCount "_" Random(1000,999999) ".db"
        try {
            ChatDB.Open(database)
            first := ChatDB.Thread_Create("A"), second := ChatDB.Thread_Create("B")
            message := ChatDB.Msg_Insert({thread_id:first,role:"user",content:"Image"})
            attachment := AttachmentRepo.Insert(message,{attachment_type:"image",file_path:"attachments\fixture.png",mime_type:"image/png"})
            if ImageAttachmentResources.AuthorizedAttachment(first,attachment).id != attachment
                throw Error("The attachment owner must be allowed to read it")
            for thread in [second,"missing-thread"] {
                threw := false
                try ImageAttachmentResources.AuthorizedAttachment(thread,attachment)
                catch
                    threw := true
                if !threw
                    throw Error("Another thread must not read this attachment")
            }
            ThreadLockRepo.Set(first,"fixture-salt","fixture-hash",600000)
            ThreadLockService.Relock(first)
            threw := false
            try ImageAttachmentResources.AuthorizedAttachment(first,attachment)
            catch
                threw := true
            if !threw
                throw Error("Locked chats must not expose image resources")
            ThreadLockService.Unlock(first)
            ImageAttachmentResources.AuthorizedAttachment(first,attachment)
        } finally {
            AppInfo.DataDir := oldRoot
            ChatDB.Close()
            try FileDelete(database)
            try DirDelete(directory)
        }
    }
}
