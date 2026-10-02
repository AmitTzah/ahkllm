; Small browser-generated previews live separately from original attachments.
#Include AppInfo.ahk
#Include ImageUtils.ahk

class ImageThumbnailCache {
    static MAX_THUMBNAIL_BYTES := 512 * 1024
    static CacheDir() => AppInfo.DataDir "\image-thumbnails"

    static SourcePath(relativePath) {
        normalized := StrReplace(relativePath, "/", "\")
        if !RegExMatch(normalized, "i)^attachments\\[a-z0-9_.-]+$")
            throw Error("Image path is outside managed attachments.")
        return AppInfo.DataDir "\" normalized
    }

    static Describe(relativePath) {
        source := ImageThumbnailCache.SourcePath(relativePath)
        if !FileExist(source)
            return { key: "", cached: false, width: 300, height: 300, source: source }
        SplitPath(source, &filename)
        key := filename "_" FileGetSize(source) "_" FileGetTime(source, "M")
        preview := ImageThumbnailCache.CacheDir() "\" key ".webp"
        width := 300, height := 300
        if FileExist(preview) {
            try width := Integer(IniRead(preview ".ini", "image", "width", 300))
            try height := Integer(IniRead(preview ".ini", "image", "height", 300))
        } else {
            dimensions := ImageThumbnailCache._HeaderDimensions(source)
            if dimensions
                width := dimensions.width, height := dimensions.height
        }
        scale := Min(300 / Max(1, width), 300 / Max(1, height), 1)
        return { key: key, cached: FileExist(preview) && FileGetSize(preview) <= ImageThumbnailCache.MAX_THUMBNAIL_BYTES,
            width: Max(48, Round(width * scale)), height: Max(48, Round(height * scale)), source: source, preview: preview }
    }

    static Save(relativePath, key, base64, originalWidth, originalHeight) {
        descriptor := ImageThumbnailCache.Describe(relativePath)
        if !descriptor.key || descriptor.key != key
            throw Error("The image changed before its thumbnail was cached.")
        if StrLen(base64) > Ceil(ImageThumbnailCache.MAX_THUMBNAIL_BYTES * 4 / 3) + 4
            throw Error("Image thumbnail is too large.")
        if !IsNumber(originalWidth) || !IsNumber(originalHeight) || originalWidth < 1 || originalHeight < 1
            || originalWidth > 65535 || originalHeight > 65535
            throw Error("Invalid image dimensions.")
        bytes := ImageUtils._Base64Decode(base64)
        if !bytes || bytes.Size < 12 || bytes.Size > ImageThumbnailCache.MAX_THUMBNAIL_BYTES
            || StrGet(bytes.Ptr, 4, "CP0") != "RIFF" || StrGet(bytes.Ptr + 8, 4, "CP0") != "WEBP"
            throw Error("Invalid WebP thumbnail.")
        DirCreate(ImageThumbnailCache.CacheDir())
        temporary := descriptor.preview ".tmp" A_TickCount "_" Random(1000, 999999)
        try {
            file := FileOpen(temporary, "w")
            file.RawWrite(bytes, bytes.Size)
            file.Close()
            FileMove(temporary, descriptor.preview, 1)
            IniWrite(originalWidth, descriptor.preview ".ini", "image", "width")
            IniWrite(originalHeight, descriptor.preview ".ini", "image", "height")
        } finally {
            try FileDelete(temporary)
        }
        return descriptor.preview
    }

    static _HeaderDimensions(path) {
        try {
            file := FileOpen(path, "r")
            header := Buffer(24, 0)
            read := file.RawRead(header, header.Size)
            file.Close()
            if read >= 24 && NumGet(header, 0, "UInt") = 0x474E5089 {
                width := ImageThumbnailCache._BigEndianUInt(header, 16)
                height := ImageThumbnailCache._BigEndianUInt(header, 20)
                if width > 0 && height > 0
                    return { width: width, height: height }
            }
            if read >= 10 && StrGet(header.Ptr, 3, "CP0") = "GIF"
                return { width: NumGet(header, 6, "UShort"), height: NumGet(header, 8, "UShort") }
        }
        return false
    }

    static _BigEndianUInt(bytes, offset) {
        return (NumGet(bytes, offset, "UChar") << 24) | (NumGet(bytes, offset + 1, "UChar") << 16)
            | (NumGet(bytes, offset + 2, "UChar") << 8) | NumGet(bytes, offset + 3, "UChar")
    }
}
