import Foundation

/// Canonical analyte catalog + normalisation, series building and correlation maths for the
/// **Biology** section. Pure Foundation — no persistence, no networking, no AI (the ScoreEngine
/// pattern), so every number below is unit-testable.
///
/// Two rules this file exists to enforce:
///
/// 1. **Nothing the user imported is ever dropped.** A parsed lab item either normalises onto a
///    canonical `AnalyteDef` or keeps the report's own name as a `.reportName` series. There is no
///    third outcome.
/// 2. **Scales are never silently mixed.** A reading is only plotted after its reported unit is
///    converted to the analyte's canonical unit; an unrecognised unit keeps its raw number, is
///    flagged `unitRecognized == false`, and is excluded from the chart line rather than drawn.
///
/// Reference ranges here are *general adult reference data* — a courtesy visualisation, not a
/// diagnosis. Callers must only ever say "outside general range"; the app gives no interpretation
/// and no advice.
enum BiologyCatalog {

    // MARK: - Definitions

    /// Which way is "better" for a rising value — drives trend-arrow colouring only. Unknown
    /// analytes have no direction and get neutral styling.
    enum Direction: String, Sendable { case inRange, lowerBetter, higherBetter }

    /// Where a *body* analyte reads from on `BodyComp` (these never appear in lab reports).
    enum BodySource: String, Sendable {
        case weight, bodyFat, leanMass, skeletalMuscle, bmi, visceralFat
    }

    /// A canonical analyte. `id` is a **persisted identifier** — never localise it, never rename it
    /// once shipped (same trap as module keys).
    struct AnalyteDef: Sendable, Equatable {
        let id: String
        let name: String
        /// Lowercase match keys. Longest wins, so put specific phrasings in alongside the short one.
        let aliases: [String]
        let category: String
        /// Canonical display unit — every point in this analyte's series is expressed in it.
        let unit: String
        /// reported-unit → multiplier onto the canonical unit. Only *linear* conversions belong
        /// here; affine ones (HbA1c mmol/mol) are deliberately absent so they read as "unit?"
        /// rather than as a wrong number.
        let altUnits: [String: Double]
        let range: ClosedRange<Double>?
        /// Only set where sex genuinely moves the range (ferritin, hemoglobin, testosterone…).
        let rangeFemale: ClosedRange<Double>?
        let direction: Direction
        let bodySource: BodySource?

        init(_ id: String, _ name: String, aliases: [String], category: String, unit: String,
             altUnits: [String: Double] = [:], range: ClosedRange<Double>? = nil,
             rangeFemale: ClosedRange<Double>? = nil, direction: Direction = .inRange,
             bodySource: BodySource? = nil) {
            self.id = id; self.name = name; self.aliases = aliases; self.category = category
            self.unit = unit; self.altUnits = altUnits; self.range = range
            self.rangeFemale = rangeFemale; self.direction = direction; self.bodySource = bodySource
        }

        func referenceRange(sexMale: Bool) -> ClosedRange<Double>? {
            sexMale ? range : (rangeFemale ?? range)
        }
    }

    // MARK: - Categories

    static let otherCategory = "other"

    static let categoryOrder: [String] = [
        "metabolic", "lipids", "cbc", "thyroid", "vitamins",
        "liver", "kidney", "hormones", "inflammation", "body", otherCategory
    ]

    static func categoryLabel(_ id: String) -> String {
        switch id {
        case "metabolic":    return "Metabolic"
        case "lipids":       return "Lipids"
        case "cbc":          return "Blood count"
        case "thyroid":      return "Thyroid"
        case "vitamins":     return "Vitamins & minerals"
        case "liver":        return "Liver"
        case "kidney":       return "Kidney"
        case "hormones":     return "Hormones"
        case "inflammation": return "Inflammation"
        case "body":         return "Body composition"
        default:             return "Other — from your reports"
        }
    }

    // MARK: - The catalog

    static let all: [AnalyteDef] = metabolic + lipids + cbc + thyroid + vitamins
                                 + liver + kidney + hormones + inflammation + body

    private static let metabolic: [AnalyteDef] = [
        AnalyteDef("glucose_fasting", "Fasting glucose",
                   aliases: ["fasting blood glucose", "fasting plasma glucose", "fasting blood sugar",
                             "blood sugar fasting", "glucose fasting", "fasting glucose", "fbs", "glucose"],
                   category: "metabolic", unit: "mg/dL", altUnits: ["mmol/l": 18.016],
                   range: 70...99, direction: .inRange),
        AnalyteDef("hba1c", "HbA1c",
                   aliases: ["glycated hemoglobin", "glycosylated hemoglobin", "glycated haemoglobin",
                             "hba1c", "hb a1c", "a1c"],
                   category: "metabolic", unit: "%", range: 4.0...5.6, direction: .lowerBetter),
        AnalyteDef("insulin_fasting", "Fasting insulin",
                   aliases: ["fasting insulin", "insulin fasting", "insulin"],
                   category: "metabolic", unit: "uIU/mL", altUnits: ["pmol/l": 0.1439],
                   range: 2...12, direction: .lowerBetter),
        AnalyteDef("uric_acid", "Uric acid",
                   aliases: ["uric acid", "serum uric acid", "urate"],
                   category: "metabolic", unit: "mg/dL", altUnits: ["umol/l": 0.0168],
                   range: 3.5...7.2, rangeFemale: 2.6...6.0, direction: .lowerBetter)
    ]

    private static let lipids: [AnalyteDef] = [
        AnalyteDef("cholesterol_total", "Total cholesterol",
                   aliases: ["total cholesterol", "cholesterol total", "serum cholesterol", "cholesterol"],
                   category: "lipids", unit: "mg/dL", altUnits: ["mmol/l": 38.67],
                   range: 125...200, direction: .lowerBetter),
        AnalyteDef("ldl", "LDL cholesterol",
                   aliases: ["ldl cholesterol", "cholesterol ldl", "ldl c", "ldl"],
                   category: "lipids", unit: "mg/dL", altUnits: ["mmol/l": 38.67],
                   range: 0...100, direction: .lowerBetter),
        AnalyteDef("hdl", "HDL cholesterol",
                   aliases: ["hdl cholesterol", "cholesterol hdl", "hdl c", "hdl"],
                   category: "lipids", unit: "mg/dL", altUnits: ["mmol/l": 38.67],
                   range: 40...90, rangeFemale: 50...90, direction: .higherBetter),
        AnalyteDef("triglycerides", "Triglycerides",
                   aliases: ["triglycerides", "triglyceride", "serum triglycerides", "tg"],
                   category: "lipids", unit: "mg/dL", altUnits: ["mmol/l": 88.57],
                   range: 0...150, direction: .lowerBetter),
        AnalyteDef("vldl", "VLDL cholesterol",
                   aliases: ["vldl cholesterol", "cholesterol vldl", "vldl"],
                   category: "lipids", unit: "mg/dL", altUnits: ["mmol/l": 38.67],
                   range: 2...30, direction: .lowerBetter),
        AnalyteDef("non_hdl", "Non-HDL cholesterol",
                   aliases: ["non hdl cholesterol", "non hdl c", "non hdl"],
                   category: "lipids", unit: "mg/dL", altUnits: ["mmol/l": 38.67],
                   range: 0...130, direction: .lowerBetter),
        AnalyteDef("lipoprotein_a", "Lp(a)",
                   aliases: ["lipoprotein a", "lipoprotein little a", "lp a", "lpa"],
                   category: "lipids", unit: "mg/dL", range: 0...30, direction: .lowerBetter),
        AnalyteDef("apo_b", "ApoB",
                   aliases: ["apolipoprotein b", "apo b", "apob"],
                   category: "lipids", unit: "mg/dL", altUnits: ["g/l": 100],
                   range: 0...90, direction: .lowerBetter)
    ]

    private static let cbc: [AnalyteDef] = [
        AnalyteDef("hemoglobin", "Hemoglobin",
                   aliases: ["hemoglobin", "haemoglobin", "hgb", "hb"],
                   category: "cbc", unit: "g/dL", altUnits: ["g/l": 0.1],
                   range: 13.5...17.5, rangeFemale: 12.0...15.5, direction: .inRange),
        AnalyteDef("hematocrit", "Hematocrit",
                   aliases: ["hematocrit", "haematocrit", "packed cell volume", "pcv", "hct"],
                   category: "cbc", unit: "%", range: 38.8...50.0, rangeFemale: 34.9...44.5),
        AnalyteDef("rbc", "Red blood cells",
                   aliases: ["red blood cell count", "red blood cells", "rbc count", "erythrocytes", "rbc"],
                   category: "cbc", unit: "10^6/uL", range: 4.5...5.9, rangeFemale: 4.1...5.1),
        AnalyteDef("wbc", "White blood cells",
                   aliases: ["white blood cell count", "white blood cells", "wbc count",
                             "total leucocyte count", "leukocytes", "tlc", "wbc"],
                   category: "cbc", unit: "10^3/uL",
                   altUnits: ["/ul": 0.001, "cells/ul": 0.001, "10^9/l": 1, "k/ul": 1],
                   range: 4.0...11.0),
        AnalyteDef("platelets", "Platelets",
                   aliases: ["platelet count", "platelets", "thrombocytes", "plt"],
                   category: "cbc", unit: "10^3/uL",
                   altUnits: ["/ul": 0.001, "cells/ul": 0.001, "10^9/l": 1, "k/ul": 1, "lakhs/cumm": 100],
                   range: 150...400),
        AnalyteDef("mcv", "MCV", aliases: ["mean corpuscular volume", "mcv"],
                   category: "cbc", unit: "fL", range: 80...100),
        // "mean corpuscular hemoglobin" is a prefix of MCHC's alias — longest-alias-first ordering
        // is what keeps MCHC from landing here.
        AnalyteDef("mch", "MCH", aliases: ["mean corpuscular hemoglobin", "mch"],
                   category: "cbc", unit: "pg", range: 27...33),
        AnalyteDef("mchc", "MCHC", aliases: ["mean corpuscular hemoglobin concentration", "mchc"],
                   category: "cbc", unit: "g/dL", range: 32...36),
        AnalyteDef("rdw", "RDW", aliases: ["red cell distribution width", "rdw cv", "rdw"],
                   category: "cbc", unit: "%", range: 11.5...14.5, direction: .lowerBetter),
        AnalyteDef("neutrophils", "Neutrophils", aliases: ["neutrophils", "neutrophil", "polymorphs"],
                   category: "cbc", unit: "%", range: 40...70),
        AnalyteDef("lymphocytes", "Lymphocytes", aliases: ["lymphocytes", "lymphocyte"],
                   category: "cbc", unit: "%", range: 20...40),
        AnalyteDef("eosinophils", "Eosinophils", aliases: ["eosinophils", "eosinophil"],
                   category: "cbc", unit: "%", range: 1...6),
        AnalyteDef("monocytes", "Monocytes", aliases: ["monocytes", "monocyte"],
                   category: "cbc", unit: "%", range: 2...10),
        AnalyteDef("basophils", "Basophils", aliases: ["basophils", "basophil"],
                   category: "cbc", unit: "%", range: 0...2),
        AnalyteDef("esr", "ESR",
                   aliases: ["erythrocyte sedimentation rate", "sedimentation rate", "esr"],
                   category: "cbc", unit: "mm/hr", range: 0...15, rangeFemale: 0...20,
                   direction: .lowerBetter)
    ]

    private static let thyroid: [AnalyteDef] = [
        AnalyteDef("tsh", "TSH",
                   aliases: ["thyroid stimulating hormone", "thyrotropin", "tsh ultrasensitive", "tsh"],
                   category: "thyroid", unit: "mIU/L", altUnits: ["uiu/ml": 1, "miu/ml": 1000],
                   range: 0.4...4.0),
        AnalyteDef("free_t4", "Free T4",
                   aliases: ["free thyroxine", "free t4", "ft4"],
                   category: "thyroid", unit: "ng/dL", altUnits: ["pmol/l": 0.0777], range: 0.8...1.8),
        AnalyteDef("free_t3", "Free T3",
                   aliases: ["free triiodothyronine", "free t3", "ft3"],
                   category: "thyroid", unit: "pg/mL", altUnits: ["pmol/l": 0.651], range: 2.3...4.2),
        AnalyteDef("total_t4", "Total T4",
                   aliases: ["total thyroxine", "total t4", "thyroxine", "t4"],
                   category: "thyroid", unit: "ug/dL", altUnits: ["nmol/l": 0.0777], range: 5.0...12.0),
        AnalyteDef("total_t3", "Total T3",
                   aliases: ["total triiodothyronine", "total t3", "triiodothyronine", "t3"],
                   category: "thyroid", unit: "ng/dL", altUnits: ["nmol/l": 65.1], range: 80...200),
        AnalyteDef("anti_tpo", "Anti-TPO",
                   aliases: ["thyroid peroxidase antibody", "anti thyroid peroxidase", "anti tpo", "tpo ab"],
                   category: "thyroid", unit: "IU/mL", range: 0...34, direction: .lowerBetter)
    ]

    private static let vitamins: [AnalyteDef] = [
        AnalyteDef("vitamin_d", "Vitamin D (25-OH)",
                   aliases: ["25 hydroxy vitamin d", "25 oh vitamin d", "vitamin d 25 hydroxy",
                             "vitamin d total", "vitamin d3", "vitamin d"],
                   category: "vitamins", unit: "ng/mL", altUnits: ["nmol/l": 0.4006],
                   range: 30...100, direction: .higherBetter),
        AnalyteDef("vitamin_b12", "Vitamin B12",
                   aliases: ["vitamin b12", "cyanocobalamin", "cobalamin", "b12"],
                   category: "vitamins", unit: "pg/mL", altUnits: ["pmol/l": 1.355], range: 200...900),
        AnalyteDef("folate", "Folate",
                   aliases: ["folic acid", "serum folate", "folate"],
                   category: "vitamins", unit: "ng/mL", altUnits: ["nmol/l": 0.4415],
                   range: 3...20, direction: .higherBetter),
        AnalyteDef("ferritin", "Ferritin",
                   aliases: ["serum ferritin", "ferritin"],
                   category: "vitamins", unit: "ng/mL", altUnits: ["ug/l": 1],
                   range: 30...400, rangeFemale: 15...200),
        AnalyteDef("iron", "Iron",
                   aliases: ["serum iron", "iron"],
                   category: "vitamins", unit: "ug/dL", altUnits: ["umol/l": 5.587],
                   range: 65...175, rangeFemale: 50...170),
        AnalyteDef("tibc", "TIBC",
                   aliases: ["total iron binding capacity", "iron binding capacity", "tibc"],
                   category: "vitamins", unit: "ug/dL", altUnits: ["umol/l": 5.587], range: 250...450),
        AnalyteDef("transferrin_sat", "Transferrin saturation",
                   aliases: ["transferrin saturation", "iron saturation", "tsat"],
                   category: "vitamins", unit: "%", range: 20...50),
        AnalyteDef("calcium", "Calcium",
                   aliases: ["serum calcium", "total calcium", "calcium"],
                   category: "vitamins", unit: "mg/dL", altUnits: ["mmol/l": 4.008], range: 8.6...10.2),
        AnalyteDef("magnesium", "Magnesium",
                   aliases: ["serum magnesium", "magnesium"],
                   category: "vitamins", unit: "mg/dL", altUnits: ["mmol/l": 2.43], range: 1.7...2.2),
        AnalyteDef("phosphorus", "Phosphorus",
                   aliases: ["inorganic phosphorus", "phosphorus", "phosphate"],
                   category: "vitamins", unit: "mg/dL", altUnits: ["mmol/l": 3.097], range: 2.5...4.5),
        AnalyteDef("sodium", "Sodium",
                   aliases: ["serum sodium", "sodium", "na"],
                   category: "vitamins", unit: "mmol/L", altUnits: ["meq/l": 1], range: 135...145),
        AnalyteDef("potassium", "Potassium",
                   aliases: ["serum potassium", "potassium"],
                   category: "vitamins", unit: "mmol/L", altUnits: ["meq/l": 1], range: 3.5...5.1),
        AnalyteDef("chloride", "Chloride",
                   aliases: ["serum chloride", "chloride"],
                   category: "vitamins", unit: "mmol/L", altUnits: ["meq/l": 1], range: 98...107),
        AnalyteDef("zinc", "Zinc",
                   aliases: ["serum zinc", "zinc"],
                   category: "vitamins", unit: "ug/dL", altUnits: ["umol/l": 6.538], range: 70...120)
    ]

    private static let liver: [AnalyteDef] = [
        AnalyteDef("alt", "ALT",
                   aliases: ["alanine aminotransferase", "alanine transaminase", "sgpt", "alt"],
                   category: "liver", unit: "U/L", range: 7...40, direction: .lowerBetter),
        AnalyteDef("ast", "AST",
                   aliases: ["aspartate aminotransferase", "aspartate transaminase", "sgot", "ast"],
                   category: "liver", unit: "U/L", range: 8...40, direction: .lowerBetter),
        AnalyteDef("alp", "ALP",
                   aliases: ["alkaline phosphatase", "alk phos", "alp"],
                   category: "liver", unit: "U/L", range: 40...130),
        AnalyteDef("ggt", "GGT",
                   aliases: ["gamma glutamyl transferase", "gamma gt", "ggtp", "ggt"],
                   category: "liver", unit: "U/L", range: 8...61, rangeFemale: 5...36,
                   direction: .lowerBetter),
        AnalyteDef("bilirubin_total", "Total bilirubin",
                   aliases: ["total bilirubin", "bilirubin total", "bilirubin"],
                   category: "liver", unit: "mg/dL", altUnits: ["umol/l": 0.0585], range: 0.2...1.2),
        AnalyteDef("bilirubin_direct", "Direct bilirubin",
                   aliases: ["direct bilirubin", "bilirubin direct", "conjugated bilirubin"],
                   category: "liver", unit: "mg/dL", altUnits: ["umol/l": 0.0585], range: 0...0.3),
        AnalyteDef("albumin", "Albumin",
                   aliases: ["serum albumin", "albumin"],
                   category: "liver", unit: "g/dL", altUnits: ["g/l": 0.1],
                   range: 3.5...5.2, direction: .higherBetter),
        AnalyteDef("total_protein", "Total protein",
                   aliases: ["total protein", "protein total", "serum protein"],
                   category: "liver", unit: "g/dL", altUnits: ["g/l": 0.1], range: 6.0...8.3)
    ]

    private static let kidney: [AnalyteDef] = [
        AnalyteDef("creatinine", "Creatinine",
                   aliases: ["serum creatinine", "creatinine"],
                   category: "kidney", unit: "mg/dL", altUnits: ["umol/l": 0.0113],
                   range: 0.7...1.3, rangeFemale: 0.6...1.1, direction: .lowerBetter),
        AnalyteDef("egfr", "eGFR",
                   aliases: ["estimated glomerular filtration rate", "glomerular filtration rate",
                             "egfr", "gfr"],
                   category: "kidney", unit: "mL/min", range: 90...150, direction: .higherBetter),
        AnalyteDef("urea", "Urea / BUN",
                   aliases: ["blood urea nitrogen", "blood urea", "urea nitrogen", "bun", "urea"],
                   category: "kidney", unit: "mg/dL", altUnits: ["mmol/l": 2.8], range: 7...20),
        AnalyteDef("cystatin_c", "Cystatin C",
                   aliases: ["cystatin c", "cystatin"],
                   category: "kidney", unit: "mg/L", range: 0.5...1.0, direction: .lowerBetter)
    ]

    private static let hormones: [AnalyteDef] = [
        AnalyteDef("testosterone_total", "Total testosterone",
                   aliases: ["total testosterone", "testosterone total", "serum testosterone", "testosterone"],
                   category: "hormones", unit: "ng/dL", altUnits: ["nmol/l": 28.84],
                   range: 300...1000, rangeFemale: 15...70),
        AnalyteDef("testosterone_free", "Free testosterone",
                   aliases: ["free testosterone", "testosterone free"],
                   category: "hormones", unit: "pg/mL", altUnits: ["pmol/l": 0.2884],
                   range: 50...210, rangeFemale: 1...8.5),
        AnalyteDef("estradiol", "Estradiol",
                   aliases: ["estradiol", "oestradiol", "e2"],
                   category: "hormones", unit: "pg/mL", altUnits: ["pmol/l": 0.2724],
                   range: 10...40, rangeFemale: 30...400),
        AnalyteDef("cortisol", "Cortisol",
                   aliases: ["morning cortisol", "serum cortisol", "cortisol"],
                   category: "hormones", unit: "ug/dL", altUnits: ["nmol/l": 0.0363], range: 6...23),
        AnalyteDef("dhea_s", "DHEA-S",
                   aliases: ["dehydroepiandrosterone sulfate", "dhea sulfate", "dhea s", "dheas"],
                   category: "hormones", unit: "ug/dL", altUnits: ["umol/l": 36.85],
                   range: 100...500, rangeFemale: 35...430),
        AnalyteDef("prolactin", "Prolactin",
                   aliases: ["prolactin", "prl"],
                   category: "hormones", unit: "ng/mL", altUnits: ["miu/l": 0.0472],
                   range: 4...15, rangeFemale: 4...23),
        AnalyteDef("shbg", "SHBG",
                   aliases: ["sex hormone binding globulin", "shbg"],
                   category: "hormones", unit: "nmol/L", range: 20...60)
    ]

    private static let inflammation: [AnalyteDef] = [
        AnalyteDef("hs_crp", "hs-CRP",
                   aliases: ["high sensitivity c reactive protein", "hs crp", "hscrp",
                             "c reactive protein", "crp"],
                   category: "inflammation", unit: "mg/L", altUnits: ["mg/dl": 10],
                   range: 0...3, direction: .lowerBetter),
        AnalyteDef("homocysteine", "Homocysteine",
                   aliases: ["homocysteine"],
                   category: "inflammation", unit: "umol/L", range: 5...15, direction: .lowerBetter)
    ]

    /// Body analytes read from `BodyComp` (InBody imports) so those series appear in the same
    /// browser with zero extra storage. They also carry aliases so a report that happens to print
    /// "Body fat %" still normalises onto the same series.
    private static let body: [AnalyteDef] = [
        AnalyteDef("body_weight", "Weight", aliases: ["body weight", "weight"],
                   category: "body", unit: "kg", altUnits: ["lb": 0.45359237, "lbs": 0.45359237],
                   bodySource: .weight),
        AnalyteDef("body_fat", "Body fat", aliases: ["body fat percentage", "body fat percent",
                                                     "percent body fat", "body fat", "pbf"],
                   category: "body", unit: "%", range: 8...20, rangeFemale: 21...33,
                   direction: .lowerBetter, bodySource: .bodyFat),
        AnalyteDef("lean_mass", "Lean mass", aliases: ["lean body mass", "fat free mass", "lean mass"],
                   category: "body", unit: "kg", altUnits: ["lb": 0.45359237, "lbs": 0.45359237],
                   direction: .higherBetter, bodySource: .leanMass),
        AnalyteDef("skeletal_muscle", "Skeletal muscle",
                   aliases: ["skeletal muscle mass", "skeletal muscle", "smm"],
                   category: "body", unit: "kg", altUnits: ["lb": 0.45359237, "lbs": 0.45359237],
                   direction: .higherBetter, bodySource: .skeletalMuscle),
        AnalyteDef("bmi", "BMI", aliases: ["body mass index", "bmi"],
                   category: "body", unit: "", range: 18.5...24.9, bodySource: .bmi),
        AnalyteDef("visceral_fat", "Visceral fat", aliases: ["visceral fat level", "visceral fat area",
                                                             "visceral fat", "vfa"],
                   category: "body", unit: "", range: 1...9, direction: .lowerBetter,
                   bodySource: .visceralFat)
    ]

    // MARK: - Lookup & normalisation

    private static let byID: [String: AnalyteDef] = {
        var m: [String: AnalyteDef] = [:]
        for d in all { m[d.id] = d }
        return m
    }()

    static func def(id: String) -> AnalyteDef? { byID[id] }

    private struct AliasEntry: Sendable {
        let alias: String
        let tokens: [String]
        let defID: String
    }

    /// Every alias, **longest first** — so "total cholesterol" is tried before "cholesterol" and
    /// "total iron binding capacity" before "iron".
    private static let aliasIndex: [AliasEntry] = {
        var out: [AliasEntry] = []
        for d in all {
            for a in d.aliases {
                let key = normalize(a)
                guard !key.isEmpty else { continue }
                out.append(AliasEntry(alias: key, tokens: key.split(separator: " ").map(String.init),
                                      defID: d.id))
            }
        }
        // Longest alias first; ties broken by id so the table is deterministic.
        out.sort { $0.alias.count == $1.alias.count ? $0.defID < $1.defID : $0.alias.count > $1.alias.count }
        return out
    }()

    /// Lowercase, drop parentheticals, turn punctuation into spaces, collapse whitespace.
    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        // Strip "(serum)", "(fasting)" … but keep the text before/after.
        while let open = s.firstIndex(of: "("), let close = s[open...].firstIndex(of: ")") {
            s.replaceSubrange(open...close, with: " ")
        }
        s = s.replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: " ")
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            if ch.isLetter || ch.isNumber { out.append(ch) }
            else if ch == "^" { out.append(ch) }
            else { out.append(" ") }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    /// Rows the catalog deliberately refuses to canonicalise: a computed ratio shares words with
    /// its ingredients ("Total Cholesterol / HDL ratio", "A/G ratio") but is a different quantity
    /// on a different scale. It still reaches the browser under its own report name.
    /// ("index" is *not* in here — BMI is literally "body mass index".)
    private static let ratioTokens: Set<String> = ["ratio"]

    /// Glucose qualifiers that mean "not fasting" — canonicalising these onto the fasting series
    /// would mix a post-meal spike into a fasting trend.
    private static let nonFastingGlucose: Set<String> = ["postprandial", "pp", "random", "ogtt", "pprandial"]

    /// Normalise a reported analyte name onto the catalog. `nil` means "unknown" — the caller keeps
    /// the report's own name; nothing is dropped.
    ///
    /// Aliases of 4 characters or fewer must match as **whole words**, so "hb" can't match "hbsag"
    /// and "t3" can't match inside a longer token. Longest-alias-first ordering does the rest:
    /// "total cholesterol" beats "cholesterol", "free t3" beats "t3", and "total iron binding
    /// capacity" beats "iron".
    static func match(name: String) -> AnalyteDef? {
        let n = normalize(name)
        guard !n.isEmpty else { return nil }
        let tokens = n.split(separator: " ").map(String.init)
        if !ratioTokens.isDisjoint(with: tokens) { return nil }
        for entry in aliasIndex {
            let hit = entry.alias.count <= 4
                ? containsSubsequence(tokens, entry.tokens)
                : (n.contains(entry.alias) || containsSubsequence(tokens, entry.tokens))
            guard hit, let d = byID[entry.defID] else { continue }
            if d.id == "glucose_fasting",
               !nonFastingGlucose.isDisjoint(with: tokens) || n.contains("post prandial") { return nil }
            return d
        }
        return nil
    }

    private static func containsSubsequence(_ tokens: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= tokens.count else { return false }
        for start in 0...(tokens.count - needle.count) {
            var ok = true
            for i in 0..<needle.count where tokens[start + i] != needle[i] { ok = false; break }
            if ok { return true }
        }
        return false
    }

    // MARK: - Units

    /// Canonical form of a unit string for comparison: lowercase, no spaces, µ→u, ℓ→l.
    static func unitKey(_ raw: String) -> String {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: "\u{00b5}", with: "u")   // MICRO SIGN
        s = s.replacingOccurrences(of: "\u{03bc}", with: "u")   // GREEK SMALL LETTER MU
        s = s.replacingOccurrences(of: "µ", with: "u")
        s = s.replacingOccurrences(of: "μ", with: "u")
        s = s.filter { !$0.isWhitespace }
        return s
    }

    /// Convert a reported value onto the analyte's canonical unit.
    /// Returns `nil` when the unit is not recognised — the caller must then keep the raw number,
    /// flag the point, and **exclude it from the chart**. Mixing scales silently would draw
    /// garbage trends.
    static func convert(value: Double, reportedUnit: String, to def: AnalyteDef) -> Double? {
        let reported = unitKey(reportedUnit)
        // No unit printed → assume the report used the canonical unit (ratios, indices, "%" panels).
        if reported.isEmpty { return value }
        if reported == unitKey(def.unit) { return value }
        for (alt, factor) in def.altUnits where unitKey(alt) == reported { return value * factor }
        return nil
    }

    // MARK: - Dates (POSIX, no Date() arithmetic — DST/timezone safe)

    /// Days since 1970-01-01 for a `yyyy-MM-dd` key (Howard Hinnant's civil-from-days, inverted).
    /// Pure integer maths: no `DateFormatter`, no calendar, no timezone.
    static func dayNumber(_ ymd: String) -> Int? {
        let parts = ymd.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        let yy = y - (m <= 2 ? 1 : 0)
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// The date a report's readings actually belong to: the printed collection date when the parser
    /// found one, else the day it was imported. Old records only ever have the import date — the
    /// backfill must never invent a collection date for them.
    static func effectiveDate(_ r: LabRecord) -> String {
        r.collectedDate.isEmpty ? r.date : r.collectedDate
    }

    // MARK: - Series

    enum SeriesKey: Hashable {
        case canonical(String)     // catalog id
        case reportName(String)    // normalised report name (unknown analyte)

        var storageKey: String {
            switch self {
            case .canonical(let id):  return "c:" + id
            case .reportName(let n):  return "r:" + n
            }
        }
    }

    struct Point: Identifiable, Equatable {
        var date: String            // yyyy-MM-dd, effective
        var value: Double           // canonical unit when `unitRecognized`, else the raw number
        var reportedUnit: String
        var unitRecognized: Bool
        var sourceID: String        // LabRecord / BodyComp id
        var sourceTitle: String

        var id: String { sourceID + "|" + date }
    }

    struct SeriesItem: Identifiable {
        let key: SeriesKey
        let displayName: String
        let def: AnalyteDef?
        let unit: String
        let points: [Point]         // ascending by date

        var id: String { key.storageKey }
        var category: String { def?.category ?? otherCategory }
        var direction: Direction { def?.direction ?? .inRange }
        /// Only unit-verified points are ever drawn.
        var chartPoints: [Point] { points.filter { $0.unitRecognized } }
        var latest: Point? { points.last }
        var hasUnknownUnits: Bool { points.contains { !$0.unitRecognized } }
    }

    /// Every measurement the user has ever had, one series per analyte.
    ///
    /// Ordering rules: points ascend by effective date; when two records land on the same date the
    /// **more recently imported** one wins (`labs` is newest-first, as `AppStore` inserts at 0).
    static func allSeries(labs: [LabRecord], bodyComps: [BodyComp]) -> [SeriesItem] {
        var pointsByKey: [SeriesKey: [String: Point]] = [:]   // key → date → point
        var displayName: [SeriesKey: String] = [:]
        var defForKey: [SeriesKey: AnalyteDef] = [:]
        var unitForKey: [SeriesKey: String] = [:]

        // Oldest import first, so a same-date re-import overwrites with the newer number.
        for record in labs.reversed() {
            let date = effectiveDate(record)
            guard !date.isEmpty else { continue }
            let title = record.title.isEmpty ? "Lab report" : record.title
            for item in record.items {
                let trimmed = item.name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                // Prefer the stored canonical id; fall back to live matching so records saved
                // before the backfill ran still normalise.
                let d = item.canonicalId.flatMap { byID[$0] } ?? match(name: trimmed)
                let key: SeriesKey = d.map { .canonical($0.id) } ?? .reportName(normalize(trimmed))
                if displayName[key] == nil { displayName[key] = d?.name ?? trimmed }
                if let d { defForKey[key] = d }
                let canonicalUnit = d?.unit ?? unitForKey[key] ?? item.unit
                unitForKey[key] = canonicalUnit

                let converted: Double?
                if let d {
                    converted = convert(value: item.value, reportedUnit: item.unit, to: d)
                } else {
                    // Unknown analyte: its own first-seen unit is the canonical one. A later report
                    // printing a different unit is flagged rather than silently merged.
                    converted = unitKey(item.unit) == unitKey(canonicalUnit) ? item.value : nil
                }
                let p = Point(date: date, value: converted ?? item.value, reportedUnit: item.unit,
                              unitRecognized: converted != nil, sourceID: record.id, sourceTitle: title)
                pointsByKey[key, default: [:]][date] = p
            }
        }

        // Body composition series — one source, no mixing with the entry-level weight (v1).
        for comp in bodyComps.sorted(by: { $0.date < $1.date }) {
            guard !comp.date.isEmpty else { continue }
            for d in body {
                guard let src = d.bodySource, let v = value(of: src, in: comp) else { continue }
                let key = SeriesKey.canonical(d.id)
                if displayName[key] == nil { displayName[key] = d.name }
                defForKey[key] = d
                unitForKey[key] = d.unit
                let p = Point(date: comp.date, value: v, reportedUnit: d.unit, unitRecognized: true,
                              sourceID: comp.id, sourceTitle: "InBody")
                pointsByKey[key, default: [:]][comp.date] = p
            }
        }

        return pointsByKey.map { key, byDate in
            SeriesItem(key: key,
                       displayName: displayName[key] ?? "Measurement",
                       def: defForKey[key],
                       unit: defForKey[key]?.unit ?? unitForKey[key] ?? "",
                       points: byDate.values.sorted { $0.date < $1.date })
        }
        .sorted { sortIndex($0) < sortIndex($1) }
    }

    /// Plan API: one analyte's series.
    static func series(for key: SeriesKey, labs: [LabRecord], bodyComps: [BodyComp]) -> [Point] {
        allSeries(labs: labs, bodyComps: bodyComps).first { $0.key == key }?.points ?? []
    }

    private static func value(of src: BodySource, in c: BodyComp) -> Double? {
        switch src {
        case .weight:         return c.weight
        case .bodyFat:        return c.bodyFat
        case .leanMass:       return c.leanMass
        case .skeletalMuscle: return c.skeletalMuscle
        case .bmi:            return c.bmi
        case .visceralFat:    return c.visceralFat
        }
    }

    private static func sortIndex(_ s: SeriesItem) -> String {
        let cat = categoryOrder.firstIndex(of: s.category) ?? categoryOrder.count
        return String(format: "%02d", cat) + "|" + s.displayName.lowercased()
    }

    // MARK: - Status & trend

    enum RangeStatus { case unknown, inRange, below, above }

    static func status(value: Double, def: AnalyteDef?, sexMale: Bool) -> RangeStatus {
        guard let r = def?.referenceRange(sexMale: sexMale) else { return .unknown }
        if value < r.lowerBound { return .below }
        if value > r.upperBound { return .above }
        return .inRange
    }

    enum Trend { case none, up, down, flat }

    /// Direction of travel between the last two *unit-verified* readings.
    static func trend(_ points: [Point]) -> Trend {
        let usable = points.filter { $0.unitRecognized }
        guard usable.count >= 2 else { return .none }
        let a = usable[usable.count - 2].value, b = usable[usable.count - 1].value
        let scale = max(abs(a), abs(b), 0.0001)
        let delta = (b - a) / scale
        if delta > 0.02 { return .up }
        if delta < -0.02 { return .down }
        return .flat
    }

    /// `true` = the move is in the analyte's better direction, `false` = worse, `nil` = neutral
    /// (no direction, or the analyte has none — unknown analytes are always neutral).
    static func trendIsGood(_ t: Trend, _ d: Direction) -> Bool? {
        switch (t, d) {
        case (.up, .higherBetter), (.down, .lowerBetter): return true
        case (.up, .lowerBetter), (.down, .higherBetter): return false
        default: return nil
        }
    }

    // MARK: - Correlations (deterministic, on-device, honest)

    /// A daily app metric (weight, readiness, sleep hours, protein) to correlate labs against.
    struct MetricSeries {
        let id: String
        let name: String
        let daily: [(date: String, value: Double)]
    }

    struct Correlation: Identifiable {
        let subject: String
        let other: String
        let r: Double
        let n: Int
        var id: String { subject + "|" + other }

        /// Plain-language, never causal. The caller always shows the footnote as well.
        var sentence: String {
            let dir = r > 0 ? "higher" : "lower"
            return "When \(other) was higher, \(subject) tended to be \(dir) "
                 + String(format: "(r = %.2f, %d readings).", r, n)
        }
    }

    /// Minimum paired readings before anything is shown at all.
    static let minPairs = 5
    /// Minimum |r| before a pair is worth a sentence.
    static let minAbsR = 0.5

    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in 0..<xs.count {
            let dx = xs[i] - mx, dy = ys[i] - my
            sxy += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        guard sxx > 0, syy > 0 else { return nil }   // zero variance → undefined, never 0
        return sxy / (sxx * syy).squareRoot()
    }

    /// Pair two analyte series by nearest date within `withinDays`. Each reading is used at most
    /// once (greedy, closest first) so a dense series can't be double-counted.
    static func pairAnalytes(_ a: [Point], _ b: [Point], withinDays: Int = 14) -> [(Double, Double)] {
        let av = a.filter { $0.unitRecognized }.compactMap { p -> (Int, Double)? in
            dayNumber(p.date).map { ($0, p.value) }
        }
        let bv = b.filter { $0.unitRecognized }.compactMap { p -> (Int, Double)? in
            dayNumber(p.date).map { ($0, p.value) }
        }
        guard !av.isEmpty, !bv.isEmpty else { return [] }
        var used = Set<Int>()
        var out: [(Double, Double)] = []
        for (day, value) in av.sorted(by: { $0.0 < $1.0 }) {
            var best: (idx: Int, dist: Int)?
            for (i, item) in bv.enumerated() where !used.contains(i) {
                let dist = abs(item.0 - day)
                if dist <= withinDays, best == nil || dist < best!.dist { best = (i, dist) }
            }
            if let best {
                used.insert(best.idx)
                out.append((value, bv[best.idx].1))
            }
        }
        return out
    }

    /// Pair an analyte series against a daily app metric using the metric's **trailing 30-day mean**
    /// ending on the reading's date — a single day's readiness against a quarterly lab is noise.
    static func pairAgainstMetric(_ a: [Point], metric: [(date: String, value: Double)],
                                  windowDays: Int = 30, minDays: Int = 5) -> [(Double, Double)] {
        var byDay: [(Int, Double)] = []
        for m in metric { if let d = dayNumber(m.date) { byDay.append((d, m.value)) } }
        guard !byDay.isEmpty else { return [] }
        var out: [(Double, Double)] = []
        for p in a where p.unitRecognized {
            guard let day = dayNumber(p.date) else { continue }
            let window = byDay.filter { $0.0 <= day && $0.0 > day - windowDays }
            guard window.count >= minDays else { continue }
            let mean = window.reduce(0.0) { $0 + $1.1 } / Double(window.count)
            out.append((p.value, mean))
        }
        return out
    }

    /// The strongest honest correlations for one analyte: other analytes (paired ±14 days) and app
    /// metrics (trailing 30-day means). Gated at `minPairs` readings and |r| ≥ `minAbsR`.
    static func correlations(for item: SeriesItem, among others: [SeriesItem],
                             metrics: [MetricSeries], limit: Int = 3) -> [Correlation] {
        var out: [Correlation] = []
        for other in others where other.key != item.key {
            let pairs = pairAnalytes(item.points, other.points)
            guard pairs.count >= minPairs,
                  let r = pearson(pairs.map(\.0), pairs.map(\.1)), abs(r) >= minAbsR else { continue }
            out.append(Correlation(subject: item.displayName, other: other.displayName,
                                   r: r, n: pairs.count))
        }
        for m in metrics {
            let pairs = pairAgainstMetric(item.points, metric: m.daily)
            guard pairs.count >= minPairs,
                  let r = pearson(pairs.map(\.0), pairs.map(\.1)), abs(r) >= minAbsR else { continue }
            out.append(Correlation(subject: item.displayName, other: m.name, r: r, n: pairs.count))
        }
        return Array(out.sorted { abs($0.r) > abs($1.r) }.prefix(limit))
    }

    /// The strongest correlations across everything the user has — the browser's summary card.
    static func topCorrelations(series: [SeriesItem], metrics: [MetricSeries],
                                limit: Int = 5) -> [Correlation] {
        var out: [Correlation] = []
        var seen = Set<String>()
        for item in series {
            for c in correlations(for: item, among: series, metrics: metrics, limit: limit) {
                let pairKey = [c.subject, c.other].sorted().joined(separator: "|")
                if seen.contains(pairKey) { continue }
                seen.insert(pairKey)
                out.append(c)
            }
        }
        return Array(out.sorted { abs($0.r) > abs($1.r) }.prefix(limit))
    }

    // MARK: - Import helpers

    /// Fill in `canonicalId` for every item that doesn't have one. Idempotent: an item that already
    /// carries an id is left alone, so a user's import history is never rewritten. An item nothing
    /// matches keeps `nil` **and its own name** — it still appears in the browser under "Other".
    /// Returns `true` when an id was actually assigned (so the caller only persists on real work).
    @discardableResult
    static func backfill(_ labs: inout [LabRecord]) -> Bool {
        var changed = false
        for r in labs.indices {
            for i in labs[r].items.indices where labs[r].items[i].canonicalId == nil {
                guard let id = match(name: labs[r].items[i].name)?.id else { continue }
                labs[r].items[i].canonicalId = id
                changed = true
            }
        }
        return changed
    }

    /// Set `canonicalId` on a freshly parsed record.
    static func normalized(_ record: LabRecord) -> LabRecord {
        var r = record
        for i in r.items.indices {
            r.items[i].canonicalId = match(name: r.items[i].name)?.id
        }
        return r
    }

    /// Re-uploading the same report is common. A candidate is a duplicate when it shares the
    /// effective date with an existing record and ≥80% of its (analyte, value) pairs match.
    static func duplicate(of candidate: LabRecord, in labs: [LabRecord]) -> LabRecord? {
        let date = effectiveDate(candidate)
        guard !date.isEmpty, !candidate.items.isEmpty else { return nil }
        func fingerprint(_ r: LabRecord) -> Set<String> {
            Set(r.items.map { item in
                let key = item.canonicalId ?? normalize(item.name)
                return key + "=" + String(format: "%.3f", item.value)
            })
        }
        let mine = fingerprint(candidate)
        for existing in labs where effectiveDate(existing) == date && !existing.items.isEmpty {
            let theirs = fingerprint(existing)
            let overlap = Double(mine.intersection(theirs).count)
            let denom = Double(max(mine.count, theirs.count))
            if denom > 0 && overlap / denom >= 0.8 { return existing }
        }
        return nil
    }
}
