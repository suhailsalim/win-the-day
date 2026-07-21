// swift-tools-version: 5.9
import PackageDescription

// Standalone test package for the app's pure, Foundation-only layer (Core/Models.swift + Engines/).
// It is deliberately NOT part of WinTheDay.xcodeproj — the app never depends on it, and no
// project.pbxproj change is needed. Run with `cd EngineTests && swift test`.
//
// SwiftPM refuses a target `path:` outside the package root ("target 'AppCore' … is outside the
// package root"), so `Sources/AppCore/**` holds relative **symlinks** to the real app sources
// rather than copies — there is exactly one copy of every file and the tests compile the same
// bytes the app ships. Add a symlink here when a new Foundation-only engine deserves coverage.
let package = Package(
    name: "EngineTests",
    platforms: [.macOS(.v14), .iOS(.v17)],
    targets: [
        .target(
            name: "AppCore",
            path: "Sources/AppCore",
            sources: ["Core/Models.swift", "Engines/ScoreEngine.swift",
                      "Engines/EatingScorer.swift", "Engines/PrayerClassifier.swift",
                      "Engines/RingEngine.swift", "Engines/ReadinessScorer.swift",
                      "Engines/SleepPlanner.swift", "Engines/PrayerTimes.swift",
                      "Engines/Milestones.swift", "Engines/ReminderEngine.swift"]),
        .testTarget(name: "EngineTests", dependencies: ["AppCore"],
                    path: "Tests/EngineTests")
    ]
)
