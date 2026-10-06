; Some compatible providers reuse an index for a different, uniquely named call ID.
class StreamingToolCallAssembler {
    static Merge(state, fragments) {
        if !(state.toolCalls is Map)
            state.toolCalls := Map()
        for fragment in fragments {
            if !(fragment is Map)
                continue
            index := fragment.Get("index", 0)
            id := fragment.Get("id", "")
            entry := this.Resolve(state.toolCalls, index, id)
            fn := fragment.Get("function", "")
            if !(fn is Map)
                continue
            name := fn.Get("name", "")
            if name != "" {
                if entry.name != "" && entry.name != name
                    throw Error("Provider changed the function name for tool call " entry.id ".")
                entry.name := name
            }
            arguments := fn.Get("arguments", "")
            if arguments != ""
                entry.arguments .= arguments
        }
    }

    static Resolve(calls, index, id) {
        target := "", identified := ""
        for key, entry in calls {
            wireIndex := entry.HasOwnProp("wireIndex") ? entry.wireIndex : key
            if wireIndex = index && (!entry.HasOwnProp("activeIndex") || entry.activeIndex)
                target := entry
            if id != "" && entry.id = id
                identified := entry
        }
        if identified != ""
            target := identified
        else if target = "" || (id != "" && target.id != "" && target.id != id) {
            target := {id: id, name: "", arguments: "", wireIndex: index, activeIndex: true}
            key := index
            if calls.Has(key) {
                key := calls.Count
                while calls.Has(key)
                    key++
            }
            calls[key] := target
        }
        for key, entry in calls {
            wireIndex := entry.HasOwnProp("wireIndex") ? entry.wireIndex : key
            if wireIndex = index
                entry.activeIndex := entry = target
        }
        target.wireIndex := index
        target.activeIndex := true
        if id != ""
            target.id := id
        return target
    }
}
