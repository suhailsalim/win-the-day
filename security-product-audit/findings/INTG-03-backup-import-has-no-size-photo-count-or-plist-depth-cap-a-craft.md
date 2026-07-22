# INTG-03 — Backup import has no size, photo-count, or plist-depth cap — a crafted or oversized archive can OOM-crash the app (self-inflicted, recoverable)

| Field | Value |
|---|---|
| **Severity** | Informational |
| **Category** | Integrity & restore |
| **Status** | CONFIRMED |
| **Area** | Backup/restore |
| **Location(s)** | _See Details below._ |

## Summary

The backup-import path reads the whole selected file into memory, JSON-decodes it, and base64-decodes every embedded photo with no bound on file size, photo count/size, or binary-plist nesting depth, so an oversized/malformed archive can exhaust memory and crash the app on import.

## Details

Every claim in the report checks out against source.

**1. Whole file slurped, no size pre-check** — `AppStore.prepareImport(from:)`:
```swift
let needsStop = url.startAccessingSecurityScopedResource()
defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
guard let raw = try? Data(contentsOf: url) else { ... }   // AppStore.swift:3571
```
No `resourceValues(forKeys: [.fileSizeKey])` check precedes the read; the entire file lands in memory.

**2. Full JSON decode holds all base64 photo strings** — `BackupService.parse` and `BackupArchive.init(from:)`:
```swift
if let archive = try? JSONDecoder().decode(BackupArchive.self, from: raw) {   // BackupBundle.swift:151
...
photos = (try? c.decode([String: String].self, forKey: .photos)) ?? [:]      // BackupBundle.swift:93
```
Every photo's base64 string is retained in the `photos` dictionary; there is no cap on the number or length of entries.

**3. Per-photo base64 decode at commit** — `BackupService.restore`:
```swift
for (name, b64) in archive.photos {
    if let raw = Data(base64Encoded: b64) { PhotoStore.write(raw, name: name) }   // BackupBundle.swift:217
}
```
Each photo is materialized as `Data` again with no size limit.

**4. Unbounded plist parse** — `BackupCodec.decode`:
```swift
guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil), ...   // BackupBundle.swift:63
```
`options: []` imposes no depth or length guard on attacker-controlled blob bytes.

The report's one imprecision: base64 decoding of photos happens at **commit** (`restore`, line 217), not during the preview/`parse` step — but the preview step already holds every base64 *string* in memory (line 93), so the unbounded-allocation exposure exists in both phases. The core claim — no size/count/depth limit anywhere on the import path — is correct.

## Failure / exploit scenario

Under threat model (b), someone hands the user a `.json` file named like a Win the Day backup, or the user re-imports a corrupted/bloated auto-backup. The user must explicitly invoke the import document picker, select the file, and (for commit) tap Confirm. A multi-hundred-MB file, or one with a huge `photos` map, forces `Data(contentsOf:)` + `JSONDecoder` + per-photo `Data(base64Encoded:)` allocations that exceed the app's memory budget, and iOS jetsam kills the process. The app relaunches cleanly on next open; no UserDefaults key is written until after `appData(in:)` validation succeeds and the user confirms, so no persisted data is lost or corrupted.

## Impact

A recoverable, self-inflicted denial of service: the app crashes while importing an oversized or malformed archive the user themselves selected. There is no data loss (commit stages and validates the main blob before writing any UserDefaults key), no corruption, no code execution, and no data exfiltration. On a single-user local iOS app this is a robustness/hardening gap, not a security vulnerability — the "attacker" can at most make the victim's app crash on an operation the victim manually initiated.

## Recommendation

Low priority. If hardened at all:

1. Check the file's declared size before reading in `prepareImport`:
```swift
let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
guard size <= 64 * 1024 * 1024 else { importMessage = "That backup is too large."; return }
```
2. In `BackupArchive.init(from:)` / `BackupService.restore`, cap `photos.count` and reject individual base64 strings above a sane per-photo ceiling.
3. Nothing to do for plist depth in practice — the blob bytes originate from the app's own `PropertyListSerialization.encode`; treat it as defense-in-depth only.

Given the local single-user threat model and the fact that the failure is a clean, recoverable crash, this can reasonably be left as-is.


---

_Finding INTG-03. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._