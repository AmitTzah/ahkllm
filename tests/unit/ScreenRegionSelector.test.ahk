; ======================================================
; ScreenRegionSelector.test.ahk - screenshot region regression tests
; ======================================================

class ScreenRegionSelectorTest {

    static __New() {
        RegisterTestClass("ScreenRegionSelectorTest")
    }

    NormalizeArea_HandlesAnyDragDirection() {
        forward := ScreenRegionSelector.NormalizeArea(20, 30, 100, 90)
        ScreenRegionSelectorTest._AssertArea(forward, 20, 30, 80, 60)

        reverse := ScreenRegionSelector.NormalizeArea(100, 90, 20, 30)
        ScreenRegionSelectorTest._AssertArea(reverse, 20, 30, 80, 60)
    }

    NormalizeArea_PreservesNegativeVirtualScreenCoordinates() {
        area := ScreenRegionSelector.NormalizeArea(-700, 120, -100, 620)
        ScreenRegionSelectorTest._AssertArea(area, -700, 120, 600, 500)
    }

    ScreenshotCommand_UsesSelectedRegionCapture() {
        srcPath := A_ScriptDir "\..\app\RequestProcessor.ahk"
        src := FileRead(srcPath)

        selectPos := InStr(src, "ScreenRegionSelector.Select()")
        capturePos := InStr(src, "ImageUtils.CaptureRegion(captureMsgId, screenshotArea)")
        cancelPos := InStr(src, "if !screenshotArea")

        if !selectPos || !capturePos || !cancelPos
            throw Error("Screenshot command must select a region, handle cancellation, and capture that region")
        if capturePos < selectPos
            throw Error("Screenshot capture must happen after region selection")
    }

    ScreenshotPrompt_SelectsRegionBeforeShowingInput() {
        srcPath := A_ScriptDir "\\..\\app\\menu\\CommandMenu.ahk"
        src := FileRead(srcPath)

        selectPos := InStr(src, "screenshotArea := ScreenRegionSelector.Select()")
        inputPos := InStr(src, "commandInputWindow.showInputWindow")
        statePos := InStr(src, "setSelectedCommand(cmd, screenshotArea)")

        if !selectPos || !inputPos || !statePos
            throw Error("Prompted screenshot commands must preselect and preserve a screenshot area")
        if selectPos > inputPos
            throw Error("Screenshot region selection must happen before the prompt input window opens")
    }

    ScreenshotPrompt_PassesPreselectedAreaToProcessor() {
        statePath := A_ScriptDir "\\..\\app\\menu\\CommandState.ahk"
        processorPath := A_ScriptDir "\\..\\app\\RequestProcessor.ahk"
        stateSrc := FileRead(statePath)
        processorSrc := FileRead(processorPath)

        if !InStr(stateSrc, "params.Push(selectedScreenshotArea)")
            throw Error("Prompted screenshot selection must be forwarded with command parameters")
        if !InStr(processorSrc, "preselectedScreenshotArea := false")
            throw Error("RequestProcessor must accept a preselected screenshot area")
        if !InStr(processorSrc, "preselectedScreenshotArea ? preselectedScreenshotArea : ScreenRegionSelector.Select()")
            throw Error("RequestProcessor must reuse the preselected area instead of asking for a second drag")
    }

    HeadlessProbe_AcceptsScreenshotStateArgument() {
        probePath := A_ScriptDir "\\..\\tests\\headless\\probe-bughunt-db.ahk"
        probeSrc := FileRead(probePath)

        if !InStr(probeSrc, "setSelectedCommand(*)")
            throw Error("headless CommandMenu stub must accept the screenshot-area argument")
        if InStr(probeSrc, "class ScreenRegionSelector")
            throw Error("DB probe must not redeclare ScreenRegionSelector already loaded by Config/SharedLib")
        if !InStr(probeSrc, "Config.ahk") || !InStr(probeSrc, "Do not redeclare it in this probe")
            throw Error("DB probe must document that Config/SharedLib supplies ScreenRegionSelector")

        thinkingProbePath := A_ScriptDir "\\..\\tests\\headless\\probe-thinking.ahk"
        thinkingProbeSrc := FileRead(thinkingProbePath)
        if !InStr(thinkingProbeSrc, "class ScreenRegionSelector")
            throw Error("thinking probe must stub ScreenRegionSelector before including CommandMenu")
    }

    static _AssertArea(area, x, y, w, h) {
        if area.X != x || area.Y != y || area.W != w || area.H != h {
            throw Error("Expected {X:" x ", Y:" y ", W:" w ", H:" h "}, got {X:"
                area.X ", Y:" area.Y ", W:" area.W ", H:" area.H "}")
        }
    }
}
