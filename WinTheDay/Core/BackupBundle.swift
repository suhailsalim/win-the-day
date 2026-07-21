import Foundation

// Full backup & restore. Everything the app owns lives in UserDefaults + Documents/photos, so a
// backup is (a) every persisted UserDefaults key, verbatim, and (b) the photo files. Blobs are
// passed through untouched rather than re-typed, so an old archive restores into a newer app
// through the same tolerant decoders the app already uses on launch.
//
// The legacy `BackupBundle` (AppData + photos) in Models.swift stays put — old exports and old
// auto-backups still have to import.

// MARK: - Keys

/// Every UserDefaults key that holds real user data. Verified by grepping `forKey:` across the app.
enum BackupKeys {
    static let appData = "suhail_health_v2"

    /// Deliberately excluded: `last_auto_backup` (device bookkeeping, meaningless on another
    /// phone) and the App-Group `snapshot` (a derived widget cache, rebuilt on next launch).
    /// API keys are in the Keychain and are never part of an archive.
    static let all: [String] = [
        // AppStore — the big JSON blobs
        appData,                    // AppData: entries, habits, catalog, labs, rings, plans…
        "suhail_ios_settings_v1",   // AppSettings
        "targets_v1",               // Targets
        "modules_v1",               // ModulePrefs
        "personalize_v1",           // Personalization
        // Coach
        "coach_threads_v1",
        "coach_active_thread_v1",
        "coach_chat_v1",            // pre-multi-thread transcript; migrated on first launch
        // AI-written text, cached per ISO week
        "week_outlook", "week_outlook_week",
        "weekly_review", "weekly_review_week",
        "day_tips_v1", "day_tips_slot_v1",
        // Focus mode
        "focus_queue_v1", "focus_duration_min",
        // Onboarding
        "onboarding_done_v1",
        // PrayerManager
        "prayer_enabled", "prayer_branch", "prayer_madhab", "prayer_hanafi", "prayer_ramadan",
        "prayer_method", "prayer_lat", "prayer_lon", "prayer_place",
        // HydrationManager
        "hyd_target", "hyd_glass", "hyd_on", "hyd_interval", "hyd_start", "hyd_end",
        // FastingManager
        "fast_on", "fast_protocol", "fast_target", "fast_start", "fast_history",
        // RamadanManager
        "ramadan_mode", "ramadan_adjust", "ramadan_autofast", "ramadan_suhoor_lead",
        "ramadan_pre_iftar", "ramadan_skips", "ramadan_autofast_day", "ramadan_seeded_year",
    ]
}

// MARK: - Value codec

/// UserDefaults values are Data, String, Bool, Int, Double, arrays and dictionaries. Wrapping each
/// one in a single-element binary plist lets all of them travel through one `[String: Data]` map
/// and come back byte-exact — the JSON blobs included, since Data survives a plist untouched.
enum BackupCodec {
    static func encode(_ value: Any) -> Data? {
        try? PropertyListSerialization.data(fromPropertyList: [value], format: .binary, options: 0)
    }

    static func decode(_ data: Data) -> Any? {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let list = obj as? [Any] else { return nil }
        return list.first
    }
}

// MARK: - Archive

/// One backup file. `formatVersion` is the only required field — that's what lets a truncated or
/// unrelated JSON file be rejected instead of silently decoding into an empty archive. Everything
/// else decodes tolerantly, per the house rule.
struct BackupArchive: Codable {
    static let currentFormatVersion = 1

    var formatVersion: Int = BackupArchive.currentFormatVersion
    var createdEpoch: Double = Date().timeIntervalSince1970
    var appVersion: String = ""
    var blobs: [String: Data] = [:]       // UserDefaults key → plist-wrapped value
    var photos: [String: String] = [:]    // filename → base64 JPEG

    var created: Date { Date(timeIntervalSince1970: createdEpoch) }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)   // required on purpose
        createdEpoch = (try? c.decode(Double.self, forKey: .createdEpoch)) ?? 0
        appVersion = (try? c.decode(String.self, forKey: .appVersion)) ?? ""
        blobs = (try? c.decode([String: Data].self, forKey: .blobs)) ?? [:]
        photos = (try? c.decode([String: String].self, forKey: .photos)) ?? [:]
    }
}

/// What the confirm sheet shows before anything is overwritten.
struct BackupSummary {
    var created: Date?
    var appVersion: String = ""
    var days = 0
    var habits = 0
    var photos = 0
    var chats = 0
    var isFullArchive = false   // false for pre-v1 exports (entries + photos only)
}

// MARK: - Build / restore

enum BackupService {
    enum RestoreError: LocalizedError {
        case unreadable
        case unknownFormat(Int)
        case noEntries

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file didn\u{2019}t look like a Win the Day backup — nothing changed."
            case .unknownFormat(let v):
                return "That backup was made by a newer version of Win the Day (format \(v)) — update the app first. Nothing changed."
            case .noEntries:
                return "That backup is missing its main data file — nothing changed."
            }
        }
    }

    // MARK: Build

    /// Snapshot every persisted key plus the photos the given entries reference.
    static func makeArchive(photoNames: Set<String>) -> BackupArchive {
        var archive = BackupArchive()
        archive.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let d = UserDefaults.standard
        for key in BackupKeys.all {
            guard let value = d.object(forKey: key), let blob = BackupCodec.encode(value) else { continue }
            archive.blobs[key] = blob
        }
        for name in photoNames {
            if let raw = PhotoStore.rawData(name) { archive.photos[name] = raw.base64EncodedString() }
        }
        return archive
    }

    // MARK: Parse

    /// Decode a backup file. Old formats (the AppData+photos bundle, and bare AppData) are lifted
    /// into an archive so there is exactly one restore path — but they're flagged as partial so a
    /// restore from one doesn't wipe settings the file never carried.
    static func parse(_ raw: Data) throws -> BackupArchive {
        if let archive = try? JSONDecoder().decode(BackupArchive.self, from: raw) {
            guard archive.formatVersion <= BackupArchive.currentFormatVersion else {
                throw RestoreError.unknownFormat(archive.formatVersion)
            }
            guard appData(in: archive) != nil else { throw RestoreError.noEntries }
            return archive
        }
        if let legacy = try? JSONDecoder().decode(BackupBundle.self, from: raw),
           !legacy.data.entries.isEmpty || !legacy.photos.isEmpty {
            return lift(legacy.data, photos: legacy.photos)
        }
        if let plain = try? JSONDecoder().decode(AppData.self, from: raw), !plain.entries.isEmpty {
            return lift(plain, photos: [:])
        }
        throw RestoreError.unreadable
    }

    /// A pre-v1 export becomes an archive carrying only the main blob (formatVersion 0 marks it).
    private static func lift(_ data: AppData, photos: [String: String]) -> BackupArchive {
        var archive = BackupArchive()
        archive.formatVersion = 0
        archive.createdEpoch = 0
        if let raw = try? JSONEncoder().encode(data), let blob = BackupCodec.encode(raw) {
            archive.blobs[BackupKeys.appData] = blob
        }
        archive.photos = photos
        return archive
    }

    static func summary(_ archive: BackupArchive) -> BackupSummary {
        var s = BackupSummary()
        s.created = archive.createdEpoch > 0 ? archive.created : nil
        s.appVersion = archive.appVersion
        s.photos = archive.photos.count
        s.isFullArchive = archive.formatVersion >= 1
        if let data = appData(in: archive) {
            s.days = data.entries.count
            s.habits = data.habits.count
        }
        if let raw = blobData(archive, "coach_threads_v1"),
           let threads = try? JSONDecoder().decode([CoachThread].self, from: raw) {
            s.chats = threads.count
        }
        return s
    }

    // MARK: Commit

    /// Stage every blob first, then write. Nothing touches UserDefaults until the whole archive has
    /// been decoded and the main blob has been proven to parse as `AppData`, so a corrupt or
    /// truncated file leaves the device exactly as it was.
    static func restore(_ archive: BackupArchive) throws {
        guard archive.formatVersion <= BackupArchive.currentFormatVersion else {
            throw RestoreError.unknownFormat(archive.formatVersion)
        }
        var staged: [(key: String, value: Any)] = []
        for key in BackupKeys.all {
            guard let blob = archive.blobs[key] else { continue }
            guard let value = BackupCodec.decode(blob) else { throw RestoreError.unreadable }
            staged.append((key, value))
        }
        guard appData(in: archive) != nil else { throw RestoreError.noEntries }

        // Commit. Photos first: a missing photo file only fails soft in the timeline, a missing
        // key would not.
        for (name, b64) in archive.photos {
            if let raw = Data(base64Encoded: b64) { PhotoStore.write(raw, name: name) }
        }
        let d = UserDefaults.standard
        for item in staged { d.set(item.value, forKey: item.key) }
        // A full archive is the whole device state, so keys it doesn't carry must go back to their
        // defaults. Partial (pre-v1) backups only ever replace what they actually contain.
        if archive.formatVersion >= 1 {
            for key in BackupKeys.all where archive.blobs[key] == nil { d.removeObject(forKey: key) }
        }
    }

    // MARK: Helpers

    private static func blobData(_ archive: BackupArchive, _ key: String) -> Data? {
        guard let blob = archive.blobs[key] else { return nil }
        return BackupCodec.decode(blob) as? Data
    }

    private static func appData(in archive: BackupArchive) -> AppData? {
        guard let raw = blobData(archive, BackupKeys.appData) else { return nil }
        return try? JSONDecoder().decode(AppData.self, from: raw)
    }
}
