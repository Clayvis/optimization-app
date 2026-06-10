import Foundation
import os

/// Catalog of tracked biomarkers plus the lab-report alias dictionary, loaded
/// from `Resources/biomarker_catalog.json` and `biomarker_aliases.json`. Both
/// files are generated verbatim from the validated reference implementation
/// (References/biomarker-tracker.html) — port, do not redesign.
enum BiomarkerCatalogError: LocalizedError {
    case resourceMissing(String)
    case decodeFailed(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "Bundled resource \(name).json is missing"
        case .decodeFailed(let name, let underlying):
            return "Could not decode \(name).json: \(underlying.localizedDescription)"
        }
    }
}

/// One catalog row. `optimal`/`normal` are inclusive [low, high] ranges in the
/// marker's canonical `unit`. `sex` restricts sex-specific markers ("male" /
/// "female"); nil means unisex.
struct BiomarkerDefinition: Codable, Sendable, Equatable {
    let name: String
    let category: String
    let unit: String
    let optimal: [Double]
    let normal: [Double]
    let sex: String?

    init(name: String, category: String, unit: String, optimal: [Double], normal: [Double], sex: String? = nil) {
        self.name = name
        self.category = category
        self.unit = unit
        self.optimal = optimal
        self.normal = normal
        self.sex = sex
    }
}

/// Classification of a measured value against its definition. Mirrors the
/// reference `evaluateMarker`: outside normal → high/low; inside normal but
/// outside optimal → warning; inside optimal → optimal.
enum BiomarkerFlag: String, Sendable, CaseIterable {
    case optimal      // reference "normal"
    case warning      // suboptimal
    case high
    case low
    case none         // missing / unparseable

    var displayLabel: String {
        switch self {
        case .optimal: return "Optimal"
        case .warning: return "Suboptimal"
        case .high: return "High"
        case .low: return "Low"
        case .none: return "—"
        }
    }
}

enum BiomarkerCatalog {
    /// Category display order, matching the reference information architecture.
    static let categoryOrder: [String] = [
        "Cardiovascular", "Metabolic", "Inflammation", "Hormones", "Thyroid",
        "CBC", "Liver", "Kidney", "Electrolytes", "Nutrients"
    ]

    /// Full catalog keyed by marker id (e.g. "glucose", "hdl_m").
    /// Loaded once per process; the bundle file cannot change at runtime.
    static let all: [String: BiomarkerDefinition] = {
        // MARK: - try? justified because a missing/corrupt bundled resource is a
        // build defect, not a runtime condition; callers degrade to an empty
        // catalog and the BiomarkerCatalogTests regression suite catches it.
        (try? load([String: BiomarkerDefinition].self, resource: "biomarker_catalog")) ?? [:]
    }()

    /// normalized lab-report name → marker id. ~180 entries from the reference.
    static let aliases: [String: String] = {
        // MARK: - try? justified because a missing/corrupt bundled resource is a
        // build defect; tests assert non-empty so it cannot regress silently.
        (try? load([String: String].self, resource: "biomarker_aliases")) ?? [:]
    }()

    /// Markers applicable to a profile sex, in catalog order.
    static func applicable(toSex sex: String) -> [String: BiomarkerDefinition] {
        all.filter { $0.value.sex == nil || $0.value.sex == sex }
    }

    /// Ids for one category, applicable to `sex`, sorted by display name.
    static func ids(inCategory category: String, sex: String) -> [String] {
        applicable(toSex: sex)
            .filter { $0.value.category == category }
            .sorted { $0.value.name < $1.value.name }
            .map(\.key)
    }

    // MARK: - Evaluation (verbatim port of evaluateMarker)

    static func evaluate(_ id: String, value: Double?) -> BiomarkerFlag {
        guard let def = all[id], let v = value, v.isFinite else { return .none }
        if v < def.normal[0] { return .low }
        if v > def.normal[1] { return .high }
        if v < def.optimal[0] || v > def.optimal[1] { return .warning }
        return .optimal
    }

    // MARK: - Alias resolution (verbatim port of normalizeName / aliasToKey)

    /// Lowercase, strip everything but alphanumerics, %, whitespace, (), -,
    /// collapse whitespace.
    static func normalizeName(_ s: String) -> String {
        let lowered = s.lowercased()
        var kept = ""
        for ch in lowered {
            if ch.isLetter && ch.isASCII || ch.isNumber || ch == "%" || ch == " " || ch == "(" || ch == ")" || ch == "-" {
                kept.append(ch)
            }
        }
        return kept.split(separator: " ").joined(separator: " ")
    }

    /// Resolve a lab-report marker name to a catalog id, remapping
    /// sex-specific markers for female profiles and rejecting markers that do
    /// not apply to the given sex. Returns nil when unrecognized.
    static func aliasToKey(_ name: String, sex: String) -> String? {
        let n = normalizeName(name)
        guard !n.isEmpty else { return nil }
        var key = aliases[n]

        if key == nil {
            // Progressive match: exact, leading-word, or trailing-word hit.
            // Longest alias first so "total cholesterol" beats "cholesterol".
            for (alias, k) in aliases.sorted(by: { $0.key.count > $1.key.count }) {
                if n == alias || n.hasPrefix(alias + " ") || n.hasSuffix(" " + alias) {
                    key = k
                    break
                }
            }
        }
        guard var resolved = key else { return nil }

        if sex == "female" {
            switch resolved {
            case "hdl_m": resolved = "hdl_f"
            case "ferritin_m": resolved = "ferritin_f"
            case "estradiol_m": resolved = "estradiol_f"
            case "testosterone_total_m": resolved = "testosterone_total_f"
            default: break
            }
        }
        guard let def = all[resolved] else { return nil }
        if let restriction = def.sex, restriction != sex { return nil }
        return resolved
    }

    // MARK: - Loading

    private static func load<T: Decodable>(_ type: T.Type, resource: String) throws -> T {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            Logger.parser.error("Biomarker resource missing: \(resource, privacy: .public)")
            throw BiomarkerCatalogError.resourceMissing(resource)
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Logger.parser.error("Biomarker resource decode failed: \(resource, privacy: .public)")
            throw BiomarkerCatalogError.decodeFailed(resource, underlying: error)
        }
    }
}
