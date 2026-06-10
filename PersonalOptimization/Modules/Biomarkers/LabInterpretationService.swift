import Foundation
import SwiftData
import os

enum LabInterpretationError: LocalizedError {
    case missingAPIKey
    case noDraw
    case generationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add an Anthropic API key in Settings to use AI interpretation."
        case .noDraw: return "No lab draw to interpret."
        case .generationFailed(let e): return "Interpretation failed: \(e.localizedDescription)"
        }
    }
}

/// Opt-in AI interpretation of a lab draw (the reference's "analyze with
/// Claude"). Builds a compact, deterministic context from the draw — flags,
/// patterns, PhenoAge, trends vs the prior draw — and asks the model for a
/// short structured read. Never auto-runs: the user taps a button, an API key
/// must be present, and the daily TokenBudgetService cap applies, matching
/// CoachService. The raw values stay on-device; only catalog names, flags, and
/// numbers go in the prompt.
@MainActor
struct LabInterpretationService {
    private let modelContext: ModelContext
    private let api: ClaudeAPIClient
    private let logger = Logger.api

    init(modelContext: ModelContext, api: ClaudeAPIClient = .shared) {
        self.modelContext = modelContext
        self.api = api
    }

    /// Generate an interpretation of the latest draw. Returns the model's text.
    /// - Throws: `LabInterpretationError`.
    func interpretLatest(profile: UserProfile) async throws -> String {
        guard let draw = LabDrawStore.latest(modelContext: modelContext) else {
            throw LabInterpretationError.noDraw
        }
        let context = buildContext(draw: draw, sex: profile.sex, dob: profile.dob)
        let budget = TokenBudgetService(modelContext: modelContext)
        do {
            let response = try await api.complete(
                model: ClaudeModel.from(string: profile.anthropicModel),
                systemPrompt: Self.systemPrompt,
                userPrompt: context,
                maxTokens: 700,
                allowFallback: true,
                budget: budget
            )
            budget.record(inputTokens: response.inputTokens, outputTokens: response.outputTokens)
            logger.info("Lab interpretation generated tokens=\(response.totalTokens, privacy: .public)")
            return response.text
        } catch ClaudeAPIError.missingAPIKey {
            throw LabInterpretationError.missingAPIKey
        } catch {
            throw LabInterpretationError.generationFailed(error)
        }
    }

    private static let systemPrompt = """
    You are a longevity-focused health analyst reviewing one person's blood panel. \
    You are NOT a doctor and must not diagnose or prescribe. Given a list of \
    biomarkers with their value, unit, optimal range, and flag, plus any detected \
    patterns and a PhenoAge estimate, produce a concise read in this structure:

    1. Headline (one sentence on overall metabolic/longevity picture).
    2. What's dialed in (2-4 optimal markers worth reinforcing).
    3. What to watch (the out-of-range / suboptimal markers, grouped, with the \
    plausible lever for each: nutrition, training, sleep, supplementation).
    4. Suggested retest or missing markers.

    Be specific and quantitative. No hedging boilerplate, no "consult a \
    professional" appendix. Under 250 words.
    """

    /// Deterministic, compact context. Only catalog names, units, ranges,
    /// flags, and numbers — never free-text notes.
    private func buildContext(draw: LabDraw, sex: String, dob: Date) -> String {
        var lines: [String] = []
        lines.append("Profile: sex=\(sex)")
        if let chrono = PhenoAgeCalculator.chronologicalAge(dob: dob, asOf: draw.date) {
            lines.append("Chronological age: \(String(format: "%.1f", chrono))")
            if let pheno = PhenoAgeCalculator.phenoAge(values: draw.values, chronologicalAge: chrono) {
                lines.append("PhenoAge: \(String(format: "%.1f", pheno)) (delta \(String(format: "%+.1f", pheno - chrono)) years)")
            } else {
                let missing = PhenoAgeCalculator.missingMarkers(in: draw.values)
                    .compactMap { BiomarkerCatalog.all[$0]?.name }
                lines.append("PhenoAge: not computable (missing \(missing.joined(separator: ", ")))")
            }
        }

        let draws = LabDrawStore.allDraws(modelContext: modelContext)
        lines.append("\nMarkers (value unit [flag] optimal=lo-hi, trend% vs first draw):")
        for category in BiomarkerCatalog.categoryOrder {
            for id in BiomarkerCatalog.ids(inCategory: category, sex: sex) where draw.values[id] != nil {
                guard let def = BiomarkerCatalog.all[id], let v = draw.values[id] else { continue }
                let flag = BiomarkerCatalog.evaluate(id, value: v).rawValue
                let optimal = def.optimal.count == 2 ? "\(trim(def.optimal[0]))-\(trim(def.optimal[1]))" : "?"
                var line = "- \(def.name): \(trim(v)) \(def.unit) [\(flag)] optimal=\(optimal)"
                if let trend = BiomarkerInsights.trendPercent(markerID: id, draws: draws) {
                    line += " trend=\(String(format: "%+.1f", trend))%"
                }
                lines.append(line)
            }
        }

        let patterns = BiomarkerInsights.detectPatterns(values: draw.values, sex: sex)
        if !patterns.isEmpty {
            lines.append("\nDetected patterns:")
            for p in patterns { lines.append("- \(p.title): \(p.detail)") }
        }
        return lines.joined(separator: "\n")
    }

    private func trim(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.2f", v)
    }
}
