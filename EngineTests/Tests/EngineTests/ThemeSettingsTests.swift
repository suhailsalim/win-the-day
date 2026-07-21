import XCTest
@testable import AppCore

/// Appearance is persisted as raw strings so a value written by a newer build (or a corrupted one)
/// degrades to a sane default instead of throwing — which, because `AppSettings` decodes as a whole,
/// would otherwise reset every setting the user has.
final class ThemeSettingsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testDefaultsFollowTheSystemInGrey() throws {
        let s = AppSettings()
        XCTAssertEqual(s.theme, .system)
        XCTAssertEqual(s.dark, .grey)
    }

    func testSettingsSavedBeforeThemingStillDecodeToSystemDefault() throws {
        let old = try decode(AppSettings.self, #"{"provider":"openai","visibleRingCount":3}"#)
        XCTAssertEqual(old.theme, .system)
        XCTAssertEqual(old.dark, .grey)
        XCTAssertEqual(old.visibleRingCount, 3)   // the rest of the blob survived
    }

    func testRoundTrip() throws {
        var s = AppSettings()
        s.themeMode = ThemeMode.dark.rawValue
        s.darkStyle = DarkStyle.black.rawValue
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.theme, .dark)
        XCTAssertEqual(back.dark, .black)
    }

    func testUnknownValuesFallBackInsteadOfThrowing() throws {
        let s = try decode(AppSettings.self, #"{"themeMode":"solarized","darkStyle":"neon"}"#)
        XCTAssertEqual(s.theme, .system)
        XCTAssertEqual(s.dark, .grey)
        // And the stored raw strings are normalised, so the bad values can't round-trip back out.
        XCTAssertEqual(s.themeMode, ThemeMode.system.rawValue)
        XCTAssertEqual(s.darkStyle, DarkStyle.grey.rawValue)
    }

    func testWrongTypeFallsBack() throws {
        let s = try decode(AppSettings.self, #"{"themeMode":42,"darkStyle":true}"#)
        XCTAssertEqual(s.theme, .system)
        XCTAssertEqual(s.dark, .grey)
    }

    func testEveryModeAndStyleRoundTripsByRawValue() throws {
        for m in ThemeMode.allCases {
            XCTAssertEqual(ThemeMode(rawValue: m.rawValue), m)
            XCTAssertFalse(m.label.isEmpty)
        }
        for d in DarkStyle.allCases {
            XCTAssertEqual(DarkStyle(rawValue: d.rawValue), d)
            XCTAssertFalse(d.label.isEmpty)
            XCTAssertFalse(d.note.isEmpty)
        }
    }
}
