# PRIV-04 — Camera/Photo-Library purpose strings claim only "nutrition label" use, but the same pickers capture lab & body-composition reports and meal photos that are sent to a third-party cloud LLM

| Field | Value |
|---|---|
| **Severity** | Low |
| **Category** | Privacy & compliance |
| **Status** | CONFIRMED |
| **Confidence** | high |
| **Location(s)** | `Info.plist`, `WinTheDay/UI/ImagePicker.swift`, `WinTheDay/Health/ImportReportView.swift`, `WinTheDay/Food/FoodLogView.swift`, `WinTheDay/Food/CatalogView.swift` |

## Summary

Both NSCameraUsageDescription and NSPhotoLibraryUsageDescription describe only reading a nutrition label to add foods/supplements, yet the shared ImagePicker also captures lab reports, InBody/body-composition reports, and meal-plate photos, and those images are transmitted to the user-selected cloud AI provider for parsing. The consent prompts understate both the scope and the off-device transmission of the most sensitive capture path.

## Details

Confirmed against source.

**Info.plist** (repo root) declares two purpose strings that both mention only nutrition labels:

- Line 9 — `NSCameraUsageDescription` = "Win the Day uses the camera to read nutrition labels and add supplements or foods to your library."
- Line 11 — `NSPhotoLibraryUsageDescription` = "Win the Day reads a photo of a nutrition label to add supplements or foods to your library."

**The picker is shared and genuinely triggers both prompts.** `WinTheDay/UI/ImagePicker.swift:13-14` sets `vc.sourceType = (source == .camera && UIImagePickerController.isSourceTypeAvailable(.camera)) ? .camera : .photoLibrary`, so on any device without a usable camera (or for a `.library` source) the flow falls back to the photo library — meaning `NSPhotoLibraryUsageDescription` legitimately applies, not just the camera string.

**Three call sites, only one of which is nutrition labels:**

1. `WinTheDay/Food/CatalogView.swift:160` — nutrition-label OCR (matches the strings).
2. `WinTheDay/Food/FoodLogView.swift:171-172` — meal-plate photos: `if let b64 = img.base64JPEG(...) { Task { await readPlate(b64) } }`; `readPlate` (line 295-297) calls `store.mealPhotoRows(imageBase64:caption:mealKey:)`.
3. `WinTheDay/Health/ImportReportView.swift:63-66` — lab and body-composition report photos: the captured image is base64-encoded into `imageBase64`, then submitted at line 202 `store.importBodyComp(text:imageBase64:health:)` and line 204 `store.prepareLabImport(text:imageBase64:)`.

**These images leave the device.** All three AppStore methods route the base64 image to the vision path of the user-selected provider via `AIEstimator` (Anthropic/OpenAI/Gemini/OpenRouter/DeepSeek/Ollama-Cloud, unless an on-device/local model is chosen). The FoodLogView path is even gated on `Providers.supportsVision(...)` (FoodLogView.swift:186), confirming the image is destined for a remote vision model. So a photo of a blood-panel or InBody report — the most sensitive capture in the app — is presented to the user under a prompt that says only "read a photo of a nutrition label," with no hint the image can be transmitted to a third party.

Severity is correctly **Low**: this is a consent-accuracy / App Store 5.1.1 transparency gap, not a technical vulnerability, and the AI feature's own UI separately discloses cloud transmission (per the app design). But the specific system consent string that gates photo access materially understates scope.

## Failure / exploit scenario

Threat model (e): App Store privacy-compliance review, plus general consent transparency. A user opens Health → Import Report to photograph a blood-test result or InBody body-composition printout. iOS shows the system photo-library/camera consent sheet backed by NSPhotoLibraryUsageDescription / NSCameraUsageDescription, which reads only "reads a photo of a nutrition label to add supplements or foods." The user grants access believing the app parses food labels. The captured lab image is base64-encoded (ImportReportView.swift:202/204) and sent to whichever cloud LLM provider is configured. The purpose string neither names lab/report or meal photos nor indicates the image can leave the device to a third party — an Apple reviewer can flag this as an inaccurate purpose string (Guideline 5.1.1), and a privacy-conscious user is not meaningfully informed at the consent gate that their most sensitive images are in scope.

## Impact

The system-level camera/photo consent prompt — the one moment iOS forces disclosure before granting access — understates what the pickers capture (lab reports, body-composition reports, meal photos, not just nutrition labels) and gives no signal that a captured image may be transmitted off-device to an external AI provider. Concrete effects: (1) an App Store 5.1.1 purpose-string-accuracy risk that can delay review; (2) a consent-transparency gap for the app's most sensitive image data. No data-integrity or unauthorized-access impact, and the AI feature UI discloses cloud transmission elsewhere, which is why this stays Low rather than Medium.

## Recommendation

Broaden both strings in Info.plist so they cover every capture path and flag off-device transmission. For example —

- `NSCameraUsageDescription`: "Win the Day uses the camera to read nutrition labels, log meals, and capture lab or body-composition reports. Photos you use with an AI feature are sent to the AI provider you selected for parsing."
- `NSPhotoLibraryUsageDescription`: mirror the same wording for chosen photos.

Keep it factual and concise (Apple rejects overly long strings). Optionally add a one-line in-context note on the ImportReportView capture button reiterating that a chosen provider will receive the image, so the disclosure sits next to the sensitive lab-report action rather than only at the system prompt.

## References

- Apple App Store Review Guideline 5.1.1 (Data Collection and Storage — purpose string accuracy)
- Apple: Requesting authorization to access the camera / photo library (usage description keys)


---

_Finding PRIV-04. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._