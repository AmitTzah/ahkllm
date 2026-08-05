; ======================================================
; SharedLib.ahk - canonical manifest for the shared layer.
;
; Every shared utility is included here. The individual
; modules ALSO self-include their own class dependencies
; (AHK v2 deduplicates #Include, so a file is parsed at
; most once per process), which means include order never
; matters and any module can be loaded standalone without
; the unresolved-identifier load hang. This manifest is
; the one-stop include for the whole shared layer:
; lib/Config.ahk and standalone probes use it instead of
; hand-listing shared files.
; ======================================================

#Include ModelParser.ahk
#Include ModelResolver.ahk
#Include SystemMessageResolver.ahk
#Include ModelPricingParser.ahk
#Include DebugLog.ahk
#Include ImageUtils.ahk
#Include AttachmentUtils.ahk
#Include AppInfo.ahk
