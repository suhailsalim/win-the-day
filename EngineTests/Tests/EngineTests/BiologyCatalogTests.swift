import XCTest
@testable import AppCore

/// The Biology section's pure layer: alias matching, unit conversion, series building and the
/// correlation maths — plus the tolerant-decode guard for the two persisted fields it adds
/// (`LabItem.canonicalId`, `LabRecord.collectedDate`).
///
/// The two invariants worth breaking a build over:
/// 1. Nothing the user imported is dropped — an unknown analyte keeps the report's own name.
/// 2. Scales are never silently mixed — an unrecognised unit is excluded from the chart, not
///    plotted against a different scale.
final class BiologyCatalogTests: XCTestCase {

    private func labs(_ records: [LabRecord]) -> [LabRecord] { records }

    private func record(_ date: String, _ title: String, _ items: [(String, Double, String)],
                        collected: String = "", id: String = UUID().uuidString) -> LabRecord {
        LabRecord(id: id, date: date, title: title,
                  items: items.map { LabItem(name: $0.0, value: $0.1, unit: $0.2) },
                  collectedDate: collected)
    }

    // MARK: - Alias matching

    func testLongestAliasWins() {
        XCTAssertEqual(BiologyCatalog.match(name: "Total Cholesterol")?.id, "cholesterol_total")
        XCTAssertEqual(BiologyCatalog.match(name: "Cholesterol, Total")?.id, "cholesterol_total")
        XCTAssertEqual(BiologyCatalog.match(name: "Cholesterol")?.id, "cholesterol_total")
        XCTAssertEqual(BiologyCatalog.match(name: "HDL Cholesterol")?.id, "hdl")
        XCTAssertEqual(BiologyCatalog.match(name: "Cholesterol - LDL")?.id, "ldl")
        XCTAssertEqual(BiologyCatalog.match(name: "Non-HDL Cholesterol")?.id, "non_hdl")
    }

    func testShortAliasCollisions() {
        // "free t3" must beat the bare "t3" alias.
        XCTAssertEqual(BiologyCatalog.match(name: "Free T3")?.id, "free_t3")
        XCTAssertEqual(BiologyCatalog.match(name: "FT3")?.id, "free_t3")
        XCTAssertEqual(BiologyCatalog.match(name: "T3")?.id, "total_t3")
        // "iron" must not swallow the binding-capacity panel.
        XCTAssertEqual(BiologyCatalog.match(name: "Total Iron Binding Capacity (TIBC)")?.id, "tibc")
        XCTAssertEqual(BiologyCatalog.match(name: "Serum Iron")?.id, "iron")
        // A <=4-char alias only matches as a whole word: "hb" must not fire inside "HBsAg".
        XCTAssertNil(BiologyCatalog.match(name: "HBsAg"))
        XCTAssertEqual(BiologyCatalog.match(name: "Hb")?.id, "hemoglobin")
        // MCHC's longer alias must not be eaten by MCH's.
        XCTAssertEqual(BiologyCatalog.match(name: "Mean Corpuscular Hemoglobin Concentration")?.id, "mchc")
        XCTAssertEqual(BiologyCatalog.match(name: "Mean Corpuscular Hemoglobin")?.id, "mch")
        // Glycated hemoglobin is HbA1c, not hemoglobin.
        XCTAssertEqual(BiologyCatalog.match(name: "Glycated Haemoglobin (HbA1c)")?.id, "hba1c")
    }

    func testRatiosAndNonFastingGlucoseAreNotCanonicalised() {
        // A computed ratio shares words with its ingredients but is a different quantity.
        XCTAssertNil(BiologyCatalog.match(name: "Total Cholesterol / HDL Ratio"))
        // A post-meal glucose must not join the fasting-glucose trend line.
        XCTAssertNil(BiologyCatalog.match(name: "Postprandial Blood Glucose"))
        XCTAssertNil(BiologyCatalog.match(name: "Random Blood Sugar"))
        XCTAssertEqual(BiologyCatalog.match(name: "Fasting Blood Sugar")?.id, "glucose_fasting")
    }

    func testUnknownAnalyteReturnsNilAndIsNeverDropped() {
        XCTAssertNil(BiologyCatalog.match(name: "Foobarase"))
        let series = BiologyCatalog.allSeries(
            labs: [record("2026-01-10", "Odd panel", [("Foobarase", 12.5, "U/L")])],
            bodyComps: [])
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].displayName, "Foobarase", "an unknown analyte keeps the report's own name")
        XCTAssertEqual(series[0].category, BiologyCatalog.otherCategory)
        XCTAssertNil(series[0].def)
        XCTAssertEqual(series[0].points.count, 1)
        XCTAssertEqual(series[0].points[0].value, 12.5)
        XCTAssertNil(BiologyCatalog.trendIsGood(.up, series[0].direction),
                     "unknown analytes get neutral trend styling")
    }

    // MARK: - Units

    func testGlucoseMmolConvertsToMgDl() {
        let def = BiologyCatalog.def(id: "glucose_fasting")!
        XCTAssertEqual(BiologyCatalog.convert(value: 5.0, reportedUnit: "mmol/L", to: def)!, 90.08, accuracy: 0.001)
        XCTAssertEqual(BiologyCatalog.convert(value: 92, reportedUnit: "mg/dL", to: def)!, 92, accuracy: 0.0001)
        XCTAssertEqual(BiologyCatalog.convert(value: 92, reportedUnit: "MG / DL", to: def)!, 92, accuracy: 0.0001)
        XCTAssertEqual(BiologyCatalog.convert(value: 92, reportedUnit: "", to: def)!, 92, accuracy: 0.0001,
                       "a report that prints no unit is assumed canonical")
        XCTAssertNil(BiologyCatalog.convert(value: 92, reportedUnit: "furlongs", to: def))
    }

    func testMicroSignVariantsAllNormalise() {
        let def = BiologyCatalog.def(id: "iron")!
        for unit in ["\u{00b5}mol/L", "\u{03bc}mol/L", "umol/l", " UMOL / L "] {
            XCTAssertEqual(BiologyCatalog.convert(value: 10, reportedUnit: unit, to: def)!,
                           55.87, accuracy: 0.001, "unit \(unit)")
        }
    }

    func testAffineConversionsAreRefusedRatherThanApproximated() {
        // HbA1c mmol/mol → % is affine, so it is deliberately absent from altUnits: better an
        // honest "unit not recognised" than a wrong number on a chart.
        let def = BiologyCatalog.def(id: "hba1c")!
        XCTAssertNil(BiologyCatalog.convert(value: 42, reportedUnit: "mmol/mol", to: def))
    }

    func testTwoReportsInDifferentUnitsGraphAsOneCoherentSeries() {
        // labs are newest-first, as AppStore stores them.
        let series = BiologyCatalog.allSeries(labs: [
            record("2026-06-01", "Euro panel", [("Fasting Glucose", 5.0, "mmol/L")]),
            record("2026-01-01", "Indian panel", [("Fasting Blood Sugar", 92, "mg/dL")])
        ], bodyComps: [])
        let glucose = series.first { $0.key == .canonical("glucose_fasting") }
        XCTAssertNotNil(glucose)
        XCTAssertEqual(glucose!.unit, "mg/dL")
        XCTAssertEqual(glucose!.chartPoints.count, 2)
        XCTAssertEqual(glucose!.points[0].value, 92, accuracy: 0.001)
        XCTAssertEqual(glucose!.points[1].value, 90.08, accuracy: 0.001)
    }

    func testUnrecognisedUnitIsKeptButExcludedFromTheChart() {
        let series = BiologyCatalog.allSeries(labs: [
            record("2026-06-01", "B", [("Fasting Glucose", 5.4, "gill/hogshead")]),
            record("2026-01-01", "A", [("Fasting Glucose", 92, "mg/dL")])
        ], bodyComps: [])
        let g = series.first { $0.key == .canonical("glucose_fasting") }!
        XCTAssertEqual(g.points.count, 2, "the reading is still listed")
        XCTAssertEqual(g.chartPoints.count, 1, "but never drawn against a different scale")
        XCTAssertTrue(g.hasUnknownUnits)
        XCTAssertEqual(g.points[1].value, 5.4, "the raw number is preserved verbatim")
        XCTAssertFalse(g.points[1].unitRecognized)
    }

    func testUnknownAnalyteFlagsAUnitChangeInsteadOfMixingScales() {
        let series = BiologyCatalog.allSeries(labs: [
            record("2026-06-01", "B", [("Foobarase", 3, "g/L")]),
            record("2026-01-01", "A", [("Foobarase", 12, "U/L")])
        ], bodyComps: [])
        let s = series[0]
        XCTAssertEqual(s.points.count, 2)
        XCTAssertEqual(s.chartPoints.count, 1)
        XCTAssertEqual(s.unit, "U/L", "the first-seen unit is the unknown analyte's canonical one")
    }

    // MARK: - Series

    func testSeriesIsSortedAndSameDayDuplicatesKeepTheNewerImport() {
        // Both reports collected on the same day; the first element of `labs` is the newer import.
        let series = BiologyCatalog.allSeries(labs: [
            record("2026-03-02", "Re-upload", [("HbA1c", 5.4, "%")], collected: "2026-03-01"),
            record("2026-03-01", "Original", [("HbA1c", 9.9, "%")], collected: "2026-03-01"),
            record("2026-01-01", "Older", [("HbA1c", 5.9, "%")])
        ], bodyComps: [])
        let a1c = series.first { $0.key == .canonical("hba1c") }!
        XCTAssertEqual(a1c.points.map(\.date), ["2026-01-01", "2026-03-01"])
        XCTAssertEqual(a1c.points[1].value, 5.4, "the more recently imported report wins the day")
    }

    func testCollectedDateOverridesImportDateAndOldRecordsFallBack() {
        let withCollected = record("2026-05-20", "Panel", [("TSH", 2.1, "mIU/L")], collected: "2026-05-01")
        XCTAssertEqual(BiologyCatalog.effectiveDate(withCollected), "2026-05-01")
        let legacy = record("2026-05-20", "Panel", [("TSH", 2.1, "mIU/L")])
        XCTAssertEqual(BiologyCatalog.effectiveDate(legacy), "2026-05-20",
                       "a pre-update record falls back to its import date; nothing is invented")
    }

    func testBodyCompsJoinTheSameBrowser() {
        let comps = [BodyComp(id: "c1", date: "2026-01-01", weight: 78, bodyFat: 19, visceralFat: 8),
                     BodyComp(id: "c2", date: "2026-04-01", weight: 75, bodyFat: 17, visceralFat: 6)]
        let series = BiologyCatalog.allSeries(labs: [], bodyComps: comps)
        let weight = series.first { $0.key == .canonical("body_weight") }!
        XCTAssertEqual(weight.points.map(\.value), [78, 75])
        XCTAssertEqual(weight.category, "body")
        XCTAssertEqual(BiologyCatalog.trend(weight.points), .down)
        let bf = series.first { $0.key == .canonical("body_fat") }!
        XCTAssertEqual(BiologyCatalog.trendIsGood(BiologyCatalog.trend(bf.points), bf.direction), true)
    }

    func testStatusUsesTheSexSpecificRangeWhereItMatters() {
        let ferritin = BiologyCatalog.def(id: "ferritin")!
        XCTAssertEqual(BiologyCatalog.status(value: 20, def: ferritin, sexMale: true), .below)
        XCTAssertEqual(BiologyCatalog.status(value: 20, def: ferritin, sexMale: false), .inRange)
        // An analyte without a female-specific range uses the general one for both.
        let tsh = BiologyCatalog.def(id: "tsh")!
        XCTAssertEqual(BiologyCatalog.status(value: 6, def: tsh, sexMale: false), .above)
        XCTAssertEqual(BiologyCatalog.status(value: 6, def: nil, sexMale: true), .unknown)
    }

    func testCatalogIdsAreUniqueAndStable() {
        let ids = BiologyCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "canonical ids are persisted — they must be unique")
        XCTAssertGreaterThanOrEqual(ids.count, 55)
        for d in BiologyCatalog.all {
            XCTAssertTrue(BiologyCatalog.categoryOrder.contains(d.category), "\(d.id) has an unlisted category")
            XCTAssertFalse(d.aliases.isEmpty, "\(d.id) has no aliases")
            // Every analyte must find itself by its own display name or first alias.
            XCTAssertEqual(BiologyCatalog.match(name: d.aliases[0])?.id, d.id, "\(d.id) can't match itself")
        }
    }

    // MARK: - Dates

    func testDayNumberIsPurePosixArithmetic() {
        XCTAssertEqual(BiologyCatalog.dayNumber("1970-01-01"), 0)
        XCTAssertEqual(BiologyCatalog.dayNumber("1970-01-02"), 1)
        XCTAssertEqual(BiologyCatalog.dayNumber("2026-03-01")! - BiologyCatalog.dayNumber("2026-02-01")!, 28)
        XCTAssertEqual(BiologyCatalog.dayNumber("2024-03-01")! - BiologyCatalog.dayNumber("2024-02-01")!, 29)
        // A DST boundary is invisible to integer day maths.
        XCTAssertEqual(BiologyCatalog.dayNumber("2026-03-30")! - BiologyCatalog.dayNumber("2026-03-28")!, 2)
        XCTAssertNil(BiologyCatalog.dayNumber(""))
        XCTAssertNil(BiologyCatalog.dayNumber("not-a-date"))
        XCTAssertNil(BiologyCatalog.dayNumber("2026-13-01"))
    }

    // MARK: - Correlations

    func testPearsonAgainstAHandComputedFixture() {
        // x = 1,2,3,4,5 ; y = 2,4,5,4,5 → r = 6 / sqrt(10 * 6) = 0.7745966692…
        let r = BiologyCatalog.pearson([1, 2, 3, 4, 5], [2, 4, 5, 4, 5])!
        XCTAssertEqual(r, 0.7745966692, accuracy: 1e-8)
        XCTAssertEqual(BiologyCatalog.pearson([1, 2, 3], [2, 4, 6])!, 1.0, accuracy: 1e-12)
        XCTAssertEqual(BiologyCatalog.pearson([1, 2, 3], [6, 4, 2])!, -1.0, accuracy: 1e-12)
        XCTAssertNil(BiologyCatalog.pearson([1, 1, 1], [1, 2, 3]), "zero variance is undefined, never 0")
        XCTAssertNil(BiologyCatalog.pearson([1], [2]))
        XCTAssertNil(BiologyCatalog.pearson([1, 2], [1]))
    }

    func testAnalytePairingRespectsTheFourteenDayWindowAndUsesEachReadingOnce() {
        func pts(_ pairs: [(String, Double)]) -> [BiologyCatalog.Point] {
            pairs.map { BiologyCatalog.Point(date: $0.0, value: $0.1, reportedUnit: "", unitRecognized: true,
                                             sourceID: $0.0, sourceTitle: "t") }
        }
        let a = pts([("2026-01-01", 1), ("2026-04-01", 2)])
        let b = pts([("2026-01-05", 10), ("2026-04-20", 20)])
        let paired = BiologyCatalog.pairAnalytes(a, b)
        XCTAssertEqual(paired.count, 1, "the April pair is 19 days apart — outside the window")
        XCTAssertEqual(paired[0].0, 1); XCTAssertEqual(paired[0].1, 10)

        let dense = pts([("2026-01-02", 7), ("2026-01-03", 8)])
        let one = pts([("2026-01-02", 100)])
        XCTAssertEqual(BiologyCatalog.pairAnalytes(dense, one).count, 1,
                       "a single reading can't be double-counted against a dense series")
    }

    func testCorrelationsAreGatedAtFivePairs() {
        func series(_ id: String, _ vals: [(String, Double)]) -> BiologyCatalog.SeriesItem {
            let def = BiologyCatalog.def(id: id)!
            return BiologyCatalog.SeriesItem(
                key: .canonical(id), displayName: def.name, def: def, unit: def.unit,
                points: vals.map { BiologyCatalog.Point(date: $0.0, value: $0.1, reportedUnit: def.unit,
                                                        unitRecognized: true, sourceID: $0.0, sourceTitle: "r") })
        }
        let dates = ["2026-01-01", "2026-02-01", "2026-03-01", "2026-04-01", "2026-05-01"]
        let ldl = series("ldl", zip(dates, [100.0, 110, 120, 130, 140]).map { ($0, $1) })
        let tri = series("triglycerides", zip(dates, [90.0, 100, 115, 128, 145]).map { ($0, $1) })
        let found = BiologyCatalog.correlations(for: ldl, among: [ldl, tri], metrics: [])
        XCTAssertEqual(found.count, 1)
        XCTAssertGreaterThan(found[0].r, 0.9)
        XCTAssertEqual(found[0].n, 5)
        XCTAssertTrue(found[0].sentence.contains("readings"))

        // Four pairs: below the gate, so nothing is shown at all.
        let shortLDL = series("ldl", zip(dates.prefix(4), [100.0, 110, 120, 130]).map { ($0, $1) })
        let shortTri = series("triglycerides", zip(dates.prefix(4), [90.0, 100, 115, 128]).map { ($0, $1) })
        XCTAssertTrue(BiologyCatalog.correlations(for: shortLDL, among: [shortLDL, shortTri], metrics: []).isEmpty)
    }

    func testMetricPairingUsesATrailingThirtyDayMean() {
        let def = BiologyCatalog.def(id: "ferritin")!
        let reading = [BiologyCatalog.Point(date: "2026-02-10", value: 80, reportedUnit: def.unit,
                                            unitRecognized: true, sourceID: "r", sourceTitle: "t")]
        // 10 days inside the window (all 8.0) and one far outside (1.0) that must be ignored.
        var daily: [(date: String, value: Double)] = []
        for d in 1...10 { daily.append((String(format: "2026-02-%02d", d), 8.0)) }
        daily.append(("2025-11-01", 1.0))
        let paired = BiologyCatalog.pairAgainstMetric(reading, metric: daily)
        XCTAssertEqual(paired.count, 1)
        XCTAssertEqual(paired[0].1, 8.0, accuracy: 1e-9)

        // Too few days in the window → no pair at all rather than a noisy one.
        let thin: [(date: String, value: Double)] = [("2026-02-09", 8), ("2026-02-08", 7)]
        XCTAssertTrue(BiologyCatalog.pairAgainstMetric(reading, metric: thin).isEmpty)
    }

    // MARK: - Import helpers

    func testBackfillIsIdempotentAndNeverRewritesAnExistingId() {
        var labs = [record("2026-01-01", "Panel", [("HbA1c", 5.4, "%"), ("Foobarase", 1, "U/L")])]
        labs[0].items[0].canonicalId = nil
        XCTAssertTrue(BiologyCatalog.backfill(&labs))
        XCTAssertEqual(labs[0].items[0].canonicalId, "hba1c")
        XCTAssertNil(labs[0].items[1].canonicalId, "an unknown analyte stays nil and keeps its name")
        XCTAssertFalse(BiologyCatalog.backfill(&labs), "a second pass changes nothing")

        // A hand-set id is never overwritten.
        labs[0].items[1].canonicalId = "ldl"
        XCTAssertFalse(BiologyCatalog.backfill(&labs))
        XCTAssertEqual(labs[0].items[1].canonicalId, "ldl")
    }

    func testStoredCanonicalIdWinsOverLiveMatching() {
        var r = record("2026-01-01", "Panel", [("Mystery Row", 5.4, "%")])
        r.items[0].canonicalId = "hba1c"
        let series = BiologyCatalog.allSeries(labs: [r], bodyComps: [])
        XCTAssertEqual(series[0].key, .canonical("hba1c"))
        XCTAssertEqual(series[0].displayName, "HbA1c")
    }

    func testDuplicateDetection() {
        let original = BiologyCatalog.normalized(
            record("2026-05-12", "Full checkup",
                   [("HbA1c", 5.4, "%"), ("LDL", 101, "mg/dL"), ("HDL", 55, "mg/dL"),
                    ("Triglycerides", 120, "mg/dL"), ("TSH", 2.2, "mIU/L")],
                   collected: "2026-05-10", id: "orig"))
        // Same collection date, same values, re-typed title → duplicate.
        let reupload = BiologyCatalog.normalized(
            record("2026-06-20", "Checkup (scan)",
                   [("Hb A1c", 5.4, "%"), ("LDL Cholesterol", 101, "mg/dL"), ("HDL Cholesterol", 55, "mg/dL"),
                    ("Triglycerides", 120, "mg/dL"), ("TSH", 2.2, "mIU/L")],
                   collected: "2026-05-10"))
        XCTAssertEqual(BiologyCatalog.duplicate(of: reupload, in: [original])?.id, "orig")

        // A genuinely different panel on the same day is not a duplicate.
        let different = BiologyCatalog.normalized(
            record("2026-06-20", "Thyroid", [("TSH", 3.9, "mIU/L"), ("Free T4", 1.1, "ng/dL")],
                   collected: "2026-05-10"))
        XCTAssertNil(BiologyCatalog.duplicate(of: different, in: [original]))

        // A different day is never a duplicate.
        let laterDay = BiologyCatalog.normalized(
            record("2026-06-20", "Full checkup",
                   [("HbA1c", 5.4, "%"), ("LDL", 101, "mg/dL"), ("HDL", 55, "mg/dL"),
                    ("Triglycerides", 120, "mg/dL"), ("TSH", 2.2, "mIU/L")],
                   collected: "2026-08-01"))
        XCTAssertNil(BiologyCatalog.duplicate(of: laterDay, in: [original]))
    }

    // MARK: - Tolerant decode (the two new persisted fields)

    func testLabRecordDecodesWithoutTheNewKeys() throws {
        // Exactly what a pre-Biology build wrote: no canonicalId, no collectedDate.
        let json = """
        {"id":"L1","date":"2025-11-02","title":"Full checkup",
         "items":[{"id":"i1","name":"HbA1c","value":5.4,"unit":"%","written":false}]}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(LabRecord.self, from: json)
        XCTAssertEqual(r.id, "L1")
        XCTAssertEqual(r.collectedDate, "", "missing collectedDate must not fail the whole record")
        XCTAssertEqual(r.items.count, 1)
        XCTAssertNil(r.items[0].canonicalId)
        XCTAssertEqual(r.items[0].name, "HbA1c")
        // And the old record still shows up in the browser, matched live.
        let series = BiologyCatalog.allSeries(labs: [r], bodyComps: [])
        XCTAssertEqual(series.first?.key, .canonical("hba1c"))
        XCTAssertEqual(series.first?.points.first?.date, "2025-11-02")
    }

    func testLabRecordRoundTripsWithTheNewFields() throws {
        var r = record("2026-05-12", "Panel", [("HbA1c", 5.4, "%"), ("Foobarase", 3, "U/L")],
                       collected: "2026-05-10", id: "L2")
        r = BiologyCatalog.normalized(r)
        let back = try JSONDecoder().decode(LabRecord.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
        XCTAssertEqual(back.collectedDate, "2026-05-10")
        XCTAssertEqual(back.items[0].canonicalId, "hba1c")
        XCTAssertNil(back.items[1].canonicalId)
    }

    func testAppDataSurvivesAGarbageLabEntry() throws {
        // A single malformed item must not take the whole labs collection with it.
        let json = """
        {"labs":[{"id":"L1","date":"2025-01-01","title":"P","items":[{"id":"i","name":"HbA1c","value":"oops","unit":"%"}]}]}
        """.data(using: .utf8)!
        let d = try JSONDecoder().decode(AppData.self, from: json)
        XCTAssertEqual(d.labs.count, 1)
        XCTAssertEqual(d.labs[0].items.count, 1)
        XCTAssertEqual(d.labs[0].items[0].value, 0, "a bad value falls back rather than throwing")
    }
}
