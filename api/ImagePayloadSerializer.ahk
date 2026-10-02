; Serialize large data URLs without repeatedly escaping their base64 bytes.
; Only a strict JSON-safe alphabet takes this path; other strings use jsongo.
class ImagePayloadSerializer {
    static Stringify(payload) {
        images := Map()
        skeleton := ImagePayloadSerializer._CopyWithImageMarkers(payload, images)
        json := jsongo.Stringify(skeleton)
        for marker, original in images
            json := StrReplace(json, '"' marker '"', '"' original '"', true)
        return json
    }

    static _CopyWithImageMarkers(value, images) {
        if value is Array {
            copy := []
            for item in value
                copy.Push(ImagePayloadSerializer._CopyWithImageMarkers(item, images))
            return copy
        }
        if value is Map {
            copy := value.Clone()
            for key, item in value
                copy[key] := ImagePayloadSerializer._CopyWithImageMarkers(item, images)
            return copy
        }
        if IsObject(value) {
            copy := {}
            for key, item in value.OwnProps()
                copy.%key% := ImagePayloadSerializer._CopyWithImageMarkers(item, images)
            return copy
        }
        if Type(value) = "String" && StrLen(value) > 4096
            && RegExMatch(value, "^data:image/[A-Za-z0-9.+-]+;base64,[A-Za-z0-9+/=]+\z") {
            guid := Buffer(16)
            if DllCall("ole32\CoCreateGuid", "Ptr", guid, "Int") != 0
                return value
            text := Buffer(80)
            DllCall("ole32\StringFromGUID2", "Ptr", guid, "Ptr", text, "Int", 40)
            marker := "AhkLLM_image_" StrGet(text)
            images[marker] := value
            return marker
        }
        return value
    }
}
