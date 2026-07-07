---
name: build
description: Build, install, and verify Win the Day on a device — the exact commands with DEVELOPER_DIR, strict concurrency, and devicectl. Use whenever asked to build, compile, install, or verify the app.
---

# Build / install / verify

`xcode-select` points at CommandLineTools — **every** xcodebuild invocation needs `DEVELOPER_DIR`.

## Standard device build
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project WinTheDay.xcodeproj -scheme WinTheDay -configuration Debug \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -derivedDataPath build/dd build
```

- **Touched a manager** (`*Manager.swift`, AppStore) → append `SWIFT_STRICT_CONCURRENCY=complete`.
  A plain build (Swift 5 mode) can pass while Xcode's Swift 6 mode fails.
- Common strict-concurrency fixes: snapshot `@MainActor` state into locals before escaping
  closures; mark pure helpers `nonisolated`; `@preconcurrency import UserNotifications`.

## Install on device
```bash
xcrun devicectl list devices   # find <DEVICE_ID>
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun devicectl device install app --device <DEVICE_ID> \
  build/dd/Build/Products/Debug-iphoneos/WinTheDay.app
```

## Engine tests (if EngineTests/ exists)
```bash
cd EngineTests && swift test
```

## Done checklist
1. Build green (strict flag if managers touched).
2. Install + sanity-check the touched screen.
3. Old data still loads (tolerant decoding) — open the app, confirm past entries render.

## Signing limits (free Apple ID)
App Groups ✅ · iCloud/CloudKit ❌ · WeatherKit ❌ (weather is Open-Meteo).
Watch wireless installs flaky (error 4000) → reinstall from the iPhone Watch app, don't debug code.
