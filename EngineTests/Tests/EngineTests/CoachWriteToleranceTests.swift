import XCTest
@testable import AppCore

/// Tolerant-decode + safety guards for the coach's staged write proposals.
///
/// These structs are persisted inside the chat threads (`coach_threads_v1`) and the write journal
/// (`coach_write_log_v1`), so AGENTS.md convention 1 applies: a missing `(try? c.decode(…))` line
/// would wipe chat history, not one field. On top of that the *safety* contract is tested here —
/// a kind or status the app doesn't recognise must decode to something inert and must never be
/// mistaken for a different, executable write.
final class CoachWriteToleranceTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - PendingCoachWrite

    func testPendingCoachWriteRoundTripsEveryField() throws {
        var w = PendingCoachWrite(kind: "logFood", date: "2026-07-04",
                                  summary: "Log 2 boiled eggs to breakfast",
                                  payloadJSON: #"{"kcal":78,"mealKey":"breakfast","name":"boiled egg","qty":2}"#)
        w.status = "confirmed"
        let back = try JSONDecoder().decode(PendingCoachWrite.self, from: JSONEncoder().encode(w))
        XCTAssertEqual(back, w, "PendingCoachWrite lost a field in a round-trip — a tolerant decode line is missing.")
    }

    func testPendingCoachWriteDecodesEmptyObjectToInertDefaults() throws {
        let w = try decode(PendingCoachWrite.self, "{}")
        XCTAssertEqual(w.kind, PendingCoachWrite.unknownKind)
        XCTAssertFalse(w.isKnownKind, "An empty record must never look like an executable write.")
        XCTAssertEqual(w.status, "rejected", "A record with no status must be inert, not pending.")
        XCTAssertFalse(w.isPending)
        XCTAssertEqual(w.payloadJSON, "{}")
    }

    func testUnknownKindFallsBackAndIsNeverExecutable() throws {
        // A model (or a newer build) naming a write we don't implement.
        let w = try decode(PendingCoachWrite.self,
                           #"{"id":"x","kind":"deleteEverything","date":"2026-07-04","summary":"s","payloadJSON":"{}","status":"pending"}"#)
        XCTAssertEqual(w.kind, PendingCoachWrite.unknownKind,
                       "An unrecognised kind must fall back to `unknown`, never throw and never be kept verbatim.")
        XCTAssertFalse(w.isKnownKind)
        XCTAssertFalse(PendingCoachWrite.kinds.contains(w.kind))
        // The fallback must not collide with a real write either.
        for known in PendingCoachWrite.kinds { XCTAssertNotEqual(w.kind, known) }
    }

    func testUnknownStatusFallsBackToRejectedNotPending() throws {
        let w = try decode(PendingCoachWrite.self,
                           #"{"kind":"logFood","status":"queued-by-a-future-build"}"#)
        XCTAssertEqual(w.kind, "logFood")
        XCTAssertEqual(w.status, "rejected")
        XCTAssertFalse(w.isPending, "An unknown status must never be treated as pending — that would let it be applied.")
    }

    func testWrongTypesDoNotThrow() throws {
        let w = try decode(PendingCoachWrite.self,
                           #"{"id":42,"kind":true,"date":[],"summary":{},"payloadJSON":7,"status":9}"#)
        XCTAssertFalse(w.id.isEmpty)
        XCTAssertEqual(w.kind, PendingCoachWrite.unknownKind)
        XCTAssertEqual(w.date, "")
        XCTAssertEqual(w.summary, "")
        XCTAssertEqual(w.payloadJSON, "{}")
        XCTAssertEqual(w.status, "rejected")
    }

    func testInitNormalizesAnUnknownKindAtConstruction() {
        let w = PendingCoachWrite(kind: "wipeDatabase", date: "2026-07-04", summary: "s", payloadJSON: "{}")
        XCTAssertFalse(w.isKnownKind)
        XCTAssertEqual(w.kind, PendingCoachWrite.unknownKind)
    }

    func testKnownKindsAreExactlyTheFiveWriteTools() {
        XCTAssertEqual(Set(PendingCoachWrite.kinds),
                       ["logFood", "setMealText", "setMealTime", "togglePrayer", "removeFood"])
    }

    // MARK: - CoachWriteRecord

    func testCoachWriteRecordRoundTrips() throws {
        let r = CoachWriteRecord(id: "abc", epoch: 1_784_000_000, kind: "setMealText",
                                 summary: "Set lunch to \u{201c}rice & dal\u{201d}",
                                 undoJSON: #"{"date":"2026-07-04","mealKey":"lunch","op":"setMealText","text":"idli"}"#)
        let back = try JSONDecoder().decode(CoachWriteRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r, "CoachWriteRecord lost a field in a round-trip — a tolerant decode line is missing.")
    }

    func testCoachWriteRecordDecodesEmptyObject() throws {
        let r = try decode(CoachWriteRecord.self, "{}")
        XCTAssertFalse(r.id.isEmpty)
        XCTAssertEqual(r.epoch, 0)
        XCTAssertEqual(r.kind, PendingCoachWrite.unknownKind)
        XCTAssertEqual(r.undoJSON, "{}")
    }

    // MARK: - ChatMessage carries the proposal

    func testChatMessageRoundTripsWithAndWithoutAPendingWrite() throws {
        let plain = ChatMessage(role: "user", text: "log 2 boiled eggs for breakfast")
        let plainBack = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(plain))
        XCTAssertEqual(plainBack, plain)
        XCTAssertNil(plainBack.pendingWrite)

        let staged = ChatMessage(role: "assistant", text: "Proposed: …",
                                 pendingWrite: PendingCoachWrite(kind: "togglePrayer", date: "2026-07-04",
                                                                 summary: "Mark Fajr as prayed",
                                                                 payloadJSON: #"{"on":true,"prayer":"fajr"}"#))
        let stagedBack = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(staged))
        XCTAssertEqual(stagedBack, staged, "ChatMessage.pendingWrite is missing its tolerant decode line.")
        XCTAssertEqual(stagedBack.pendingWrite?.status, "pending")
    }

    /// A thread written before this feature existed has no `pendingWrite` key at all — it must
    /// still load, or every prior chat is wiped on the next launch.
    func testLegacyChatMessageStillDecodes() throws {
        let m = try decode(ChatMessage.self, #"{"id":"m1","role":"assistant","text":"hello"}"#)
        XCTAssertEqual(m.text, "hello")
        XCTAssertNil(m.pendingWrite)
    }

    func testChatMessageSurvivesAGarbagePendingWrite() throws {
        let m = try decode(ChatMessage.self, #"{"role":"assistant","text":"hi","pendingWrite":"nonsense"}"#)
        XCTAssertEqual(m.text, "hi", "A malformed proposal must not take the whole message (and thread) down.")
        XCTAssertNil(m.pendingWrite)
    }

    func testThreadWithAStagedWriteRoundTrips() throws {
        var t = CoachThread()
        t.title = "Meals"
        t.messages = [ChatMessage(role: "user", text: "log an egg"),
                      ChatMessage(role: "assistant", text: "Proposed: Log egg to breakfast",
                                  pendingWrite: PendingCoachWrite(kind: "logFood", date: "2026-07-04",
                                                                  summary: "Log egg to breakfast",
                                                                  payloadJSON: #"{"kcal":78}"#))]
        let back = try JSONDecoder().decode(CoachThread.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
    }

    // MARK: - Settings toggle

    func testCoachWritesEnabledDefaultsOnAndSurvivesLegacySettings() throws {
        XCTAssertTrue(AppSettings().coachWritesEnabled)
        // Settings saved before the flag existed must not silently disable the feature.
        let legacy = try decode(AppSettings.self, #"{"provider":"anthropic","model":"sonnet46"}"#)
        XCTAssertTrue(legacy.coachWritesEnabled)

        var s = AppSettings()
        s.coachWritesEnabled = false
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertFalse(back.coachWritesEnabled, "AppSettings.coachWritesEnabled is missing its tolerant decode line.")
    }
}
