# INTG-01 — Path traversal / arbitrary sandbox file write via attacker-controlled photo filenames on backup restore

| Field | Value |
|---|---|
| **Severity** | Medium |
| **Category** | Integrity & restore |
| **Status** | CONFIRMED |
| **Location(s)** | _See Details below._ |

## Summary

On backup restore, photo filenames are taken verbatim from the untrusted backup JSON and passed unsanitized to a raw file write, letting a crafted backup write attacker-controlled bytes to any path inside the app's sandbox container (via `..` traversal out of Documents/photos).

## Details

`BackupArchive.photos` is a `[String: String]` (filename → base64 JPEG) decoded straight from the imported file with no constraints:

```swift
// BackupBundle.swift:81
var photos: [String: String] = [:]    // filename → base64 JPEG
// BackupBundle.swift:93
photos = (try? c.decode([String: String].self, forKey: .photos)) ?? [:]
```

On restore, each dictionary **key** becomes the destination filename and each **value** becomes the file contents, with no validation of either:

```swift
// BackupBundle.swift:216-217
for (name, b64) in archive.photos {
    if let raw = Data(base64Encoded: b64) { PhotoStore.write(raw, name: name) }
}
```

`PhotoStore.write` performs the write with no sanitization whatsoever:

```swift
// PhotoStore.swift:37-38
static func write(_ data: Data, name: String) {
    try? data.write(to: dir.appendingPathComponent(name))
}
```

`URL.appendingPathComponent` embeds `/` and `..` components literally rather than stripping them, and `Data.write(to:)` lets the kernel resolve `..` at write time. A key such as `../../Library/Preferences/group.com.suhail.WinTheDay.plist` therefore resolves out of `Documents/photos` to anywhere inside the app's data container. There is no `lastPathComponent` reduction, no `..` rejection, no UUID/extension check, and no JPEG-magic-byte validation — the attacker controls both the full destination path and the full file contents (`Data(base64Encoded:)` of an attacker-chosen string).

Both restore entry points are reachable. The v1 path decodes `BackupArchive` directly (BackupBundle.swift:151). The legacy path (BackupBundle.swift:158-177) accepts a bare `{"data":…,"photos":{…}}` JSON with no `formatVersion` and copies `legacy.photos` verbatim into `archive.photos` via `lift(_:photos:)` (line 176), so the traversal works even without a valid v1 header.

Crucially, the malicious photos are written (line 217) **before** any UserDefaults key is written (line 220). The only pre-write guard is that the main `AppData` blob parses (line 212) — it does not inspect photo keys — so the file write lands regardless.

Legitimate filenames are always `UUID().uuidString + ".jpg"` (PhotoStore.swift:22), confirming that traversal keys can only originate from a crafted archive, not from normal exports.

## Failure / exploit scenario

Under threat model (b), an attacker crafts `win-the-day-backup.json` containing a minimal valid `AppData` blob (so `appData(in:)` passes) plus:

```json
"photos": { "../../Library/Preferences/group.com.suhail.WinTheDay.plist": "<base64 attacker bytes>" }
```

The user receives the file (AirDrop, iCloud/Files share, "here's my old backup"), imports it via the Settings restore flow (`AppStore.beginRestore` → `BackupService.parse`, AppStore.swift:3576). The confirm sheet renders only aggregate counts — `row("Photos", value: "\(summary.photos)")` (SettingsPages.swift:1301) shows e.g. "Photos 1" and never the destination path. On Confirm, `commitPendingRestore` (AppStore.swift:3593) calls `BackupService.restore`, which writes the attacker bytes to the traversed path (BackupBundle.swift:216-217) before any UserDefaults mutation. Variants: overwrite an existing `<uuid>.jpg` to tamper meal/lab/InBody health photos, or overwrite the auto-backup file to poison future restores.

## Impact

Arbitrary file write/overwrite anywhere inside the app's sandbox container, with fully attacker-controlled contents, gated only on the user importing a crafted backup file — a file type explicitly meant to be shared and re-imported. iOS sandboxing confines the write to this app's container (no cross-app or system compromise), but within that boundary the attacker can: tamper or replace existing health photos (meal/lab/InBody records) with deceptive content; clobber the UserDefaults `Preferences` plist to corrupt or inject app state; overwrite the app's own auto-backup so a later "safe" restore re-delivers attacker data; or drop arbitrary files. The restore confirmation surfaces only counts, so the user has no opportunity to see or reject the malicious paths.

## Recommendation

Sanitize photo filenames before writing, at the restore boundary and defensively in `PhotoStore`. Reduce to the last path component and reject anything that is not a plain photo name, e.g.:

```swift
static func write(_ data: Data, name: String) {
    let leaf = (name as NSString).lastPathComponent
    guard !leaf.isEmpty, leaf != ".", leaf != "..",
          !leaf.contains("/"),
          leaf.range(of: "^[A-Za-z0-9-]+\\.jpg$", options: .regularExpression) != nil
    else { return }
    let target = dir.appendingPathComponent(leaf).standardizedFileURL
    guard target.path.hasPrefix(dir.standardizedFileURL.path + "/") else { return }
    try? data.write(to: target)
}
```

Additionally, in `BackupService.restore` skip (rather than silently coerce) any `archive.photos` key failing the same predicate, and reject entries whose decoded bytes are not a JPEG (magic bytes `FF D8 FF`). Apply the same leaf-only + prefix guard in `load`, `rawData`, and `delete` for defense in depth. Since valid names are always UUIDs, this rejects nothing legitimate.


---

_Finding INTG-01. Part of the Win the Day security & product audit — see [README](../README.md) and [APPENDIX](../APPENDIX.md)._