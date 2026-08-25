; AhkLLM original implementation.
;
; The historical AutoXYWH source was identified as a 2015 AutoHotkey v1
; forum implementation by tmplinshi, with later modifications/conversion,
; but no redistribution license could be established. The application only
; needs proportional x/y movement and w/h resizing for InputWindow, so this
; small implementation is authored for AhkLLM rather than redistributing that
; unknown-license code.

AutoXYWH(DimSize, controls*) {
    static snapshots := Map()

    if DimSize = "reset"
        return snapshots := Map()

    dimensions := Map()
    normalized := StrLower(DimSize)
    for axis in ["x", "y", "w", "h"] {
        if !InStr(normalized, axis)
            continue
        if RegExMatch(normalized, axis "\s*(-?(?:\d+(?:\.\d*)?|\.\d+))", &match)
            dimensions[axis] := match[1] + 0
        else
            dimensions[axis] := 1
    }

    for control in controls {
        control.Gui.GetPos(,, &guiWidth, &guiHeight)
        if !snapshots.Has(control) {
            control.GetPos(&x, &y, &width, &height)
            snapshots[control] := {
                x: x, y: y, width: width, height: height,
                guiWidth: guiWidth, guiHeight: guiHeight
            }
            continue
        }

        prior := snapshots[control]
        deltaWidth := guiWidth - prior.guiWidth
        deltaHeight := guiHeight - prior.guiHeight
        control.Move(
            dimensions.Has("x") ? prior.x + deltaWidth * dimensions["x"] : unset,
            dimensions.Has("y") ? prior.y + deltaHeight * dimensions["y"] : unset,
            dimensions.Has("w") ? prior.width + deltaWidth * dimensions["w"] : unset,
            dimensions.Has("h") ? prior.height + deltaHeight * dimensions["h"] : unset)
    }
}
