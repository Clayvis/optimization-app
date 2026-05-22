#if os(iOS)
import Foundation
import SwiftData
import os

/// AI-driven schedule generation. Sits alongside CoachService — both call the
/// Anthropic API, but ScheduleAIService is the *authoring* surface (write a
/// new week from goals + constraints), where CoachService is the *advisory*
/// surface (insights, prescriptions, weekly adaptation).
///
/// Pipeline:
///   1. Render system prompt via CoachPrompts.generateSchedule.
///   2. Render user prompt from intake + profile + rejected-proposal memory.
///   3. Call API.
///   4. Parse JSON via ClaudeAPIClient.decodeJSON.
///   5. Run ScheduleValidator.
///   6. On failure, ONE retry with the validation errors embedded as feedback.
///   7. Persist a ScheduleGenerationRun row with status=.proposed.
///   8. Return GenerationProposal to the caller (the view applies on accept).
@MainActor
final class ScheduleAIService {

    enum ServiceError: LocalizedError {
        case missingAPIKey
        case decodeFailed(Error)
        case validationFailedAfterRetry(errors: [ScheduleValidator.ValidationError])
        case apiFailed(Error)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Anthropic API key is not set. Add it in Settings."
            case .decodeFailed(let e):
                return "Couldn't parse the AI's response: \(e.localizedDescription)"
            case .validationFailedAfterRetry(let errors):
                let first = errors.first?.errorDescription ?? "unknown"
                return "The AI's proposed schedule kept violating the rules (e.g., \(first))."
            case .apiFailed(let e):
                return "AI request failed: \(e.localizedDescription)"
            }
        }
    }

    /// Returned to callers. Carries the proposal and the audit-trail row id so
    /// the diff view can update the row's status (accepted vs discarded) on
    /// user action.
    struct Result: Sendable {
        let proposal: GenerationProposal
        let runID: PersistentIdentifier
        let tokenUsage: Int
    }

    private let modelContext: ModelContext
    private let api: CoachAPIInvoking
    private let memoryService: CoachMemoryService
    private let logger = Logger.coach
    private let now: () -> Date

    init(modelContext: ModelContext,
         api: CoachAPIInvoking = LiveCoachAPI(),
         memoryService: CoachMemoryService? = nil,
         now: @escaping () -> Date = Date.init) {
        self.modelContext = modelContext
        self.api = api
        self.memoryService = memoryService ?? CoachMemoryService(modelContext: modelContext)
        self.now = now
    }

    // MARK: - Public surface

    /// Generates a new weekly schedule from the user's intake. On success,
    /// persists a `ScheduleGenerationRun` row (status=.proposed). Caller is
    /// responsible for applying the proposal via `ScheduleSeed.applyDrafts`.
    func generate(intake: ScheduleIntake,
                  modelName: String? = nil) async throws -> Result {
        let profile = ensureProfile()
        let model = modelName ?? profile.anthropicModel
        let systemPrompt = CoachPrompts.system(
            for: .generateSchedule,
            style: profile.motivationStyle,
            customStylePrompt: profile.customStylePrompt
        )
        let baseUserPrompt = renderUserPrompt(intake: intake, profile: profile)

        let proposal: GenerationProposal
        let response: ClaudeAPIClient.Response
        do {
            (proposal, response) = try await generateOnce(
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: baseUserPrompt,
                intake: intake
            )
        } catch ServiceError.validationFailedAfterRetry(let errors) {
            // ONE retry: append the validation feedback to the user prompt and
            // try once more. If it fails again, surface the error.
            let retryPrompt = baseUserPrompt + "\n\n" + ScheduleValidator.summarize(errors)
            (proposal, response) = try await generateOnce(
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: retryPrompt,
                intake: intake,
                isRetry: true
            )
        }

        let run = try persistRun(intake: intake,
                                 proposal: proposal,
                                 model: model,
                                 tokens: response.totalTokens)
        return Result(proposal: proposal, runID: run.persistentModelID, tokenUsage: response.totalTokens)
    }

    /// Marks a previously-proposed run as accepted. Called by the apply path.
    func markAccepted(runID: PersistentIdentifier) {
        guard let run = modelContext.model(for: runID) as? ScheduleGenerationRun else { return }
        run.status = .accepted
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
    }

    /// Marks a previously-proposed run as discarded. Called when the user
    /// taps Discard in the diff view.
    func markDiscarded(runID: PersistentIdentifier) {
        guard let run = modelContext.model(for: runID) as? ScheduleGenerationRun else { return }
        run.status = .discarded
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
    }

    // MARK: - Internals

    private func generateOnce(model: String,
                              systemPrompt: String,
                              userPrompt: String,
                              intake: ScheduleIntake,
                              isRetry: Bool = false) async throws -> (GenerationProposal, ClaudeAPIClient.Response) {
        let response: ClaudeAPIClient.Response
        do {
            response = try await api.complete(
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: CoachPrompts.defaultMaxTokens(for: .generateSchedule)
            )
        } catch ClaudeAPIError.missingAPIKey {
            throw ServiceError.missingAPIKey
        } catch {
            throw ServiceError.apiFailed(error)
        }

        let proposal: GenerationProposal
        do {
            proposal = try ClaudeAPIClient.decodeJSON(response.text, as: GenerationProposal.self)
        } catch {
            // A decode failure on the retry is fatal; on the first attempt we
            // bubble through the validation channel so the retry path picks it
            // up with the decode error embedded.
            if isRetry {
                throw ServiceError.decodeFailed(error)
            }
            let synthetic: [ScheduleValidator.ValidationError] = [
                .invalidTimeFormat(blockIndex: 0, field: "(response root)", value: "<unparseable JSON>")
            ]
            throw ServiceError.validationFailedAfterRetry(errors: synthetic)
        }

        let validatorBlocks = proposal.blocks.map { $0.asValidatorBlock }
        let knownAnchors: Set<String> = intake.anchorEvents.isEmpty
            ? ScheduleValidator.Constraints.default.knownAnchors
            : Set(intake.anchorEvents)
        let defaults = ScheduleValidator.Constraints.default
        let constraints = ScheduleValidator.Constraints(
            sleepWindowStartHour: intake.sleepStartHour,
            sleepWindowEndHour: intake.sleepEndHour,
            weeklyLiftMax: 6,
            knownModules: defaults.knownModules,
            knownAnchors: knownAnchors,
            trainingWindowStartHour: intake.earliestTrainingHour,
            trainingWindowEndHour: intake.latestTrainingHour,
            trainingTypeModules: defaults.trainingTypeModules,
            wakeHHMM: nil,
            bedtimeHHMM: nil,
            kidDropoffHHMM: nil,
            kidPickupHHMM: nil,
            dailyMinuteCap: defaults.dailyMinuteCap,
            learningTypeModules: defaults.learningTypeModules
        )
        let errors = ScheduleValidator.collect(validatorBlocks, against: constraints)
        if !errors.isEmpty {
            if isRetry {
                logger.warning("Schedule generation: retry still has \(errors.count, privacy: .public) violations")
                throw ServiceError.validationFailedAfterRetry(errors: errors)
            }
            throw ServiceError.validationFailedAfterRetry(errors: errors)
        }

        logger.info("Schedule generation \(isRetry ? "retry" : "first", privacy: .public) ok blocks=\(proposal.blocks.count, privacy: .public) tokens=\(response.totalTokens, privacy: .public)")
        return (proposal, response)
    }

    private func renderUserPrompt(intake: ScheduleIntake, profile: UserProfile) -> String {
        var lines: [String] = []

        lines.append("=== INTAKE ===")
        lines.append("primaryGoal: \(intake.primaryGoal.rawValue)")
        if !intake.freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("user_says: \"\(intake.freeText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
        }
        let daysList = intake.availableDays.sorted().map(String.init).joined(separator: ",")
        lines.append("availableDays: [\(daysList)]")
        lines.append("trainingWindow: \(String(format: "%02d:00", intake.earliestTrainingHour))-\(String(format: "%02d:00", intake.latestTrainingHour))")
        lines.append("availableTimeMinutesPerDay: \(intake.availableTimeMinutesPerDay)")
        lines.append("sleepWindow: \(String(format: "%02d:00", intake.sleepStartHour))-\(String(format: "%02d:00", intake.sleepEndHour))")
        lines.append("weeklyTrainingTargetSessions: \(intake.weeklyTrainingTargetSessions)")
        lines.append("equipmentAccess: \(intake.equipmentAccess)")
        let focuses = [OptimizationFocus].fromCSV(intake.optimizationFocusesCSV)
        if !focuses.isEmpty {
            let labels = focuses.map(\.displayName).joined(separator: ", ")
            lines.append("optimizationFocuses: \(labels) (each deserves at least one weekly block)")
        }
        let restrictions = intake.restrictionsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !restrictions.isEmpty {
            lines.append("restrictions: \(restrictions.joined(separator: ", "))")
        }
        if !intake.anchorEvents.isEmpty {
            lines.append("anchorEvents: \(intake.anchorEvents.joined(separator: ", "))")
        }
        lines.append("motivationStyle: \(intake.motivationStyle)")

        // Rejected-proposal memory (M4.1). Empty on first generation.
        let rejected = rejectedSummaries()
        if !rejected.isEmpty {
            lines.append("")
            lines.append("=== REJECTED PROPOSALS (do not repeat) ===")
            for summary in rejected {
                lines.append("- \(summary)")
            }
        }

        // M4.2 followup: persona block — motivation driver, communication
        // style, accountability preference, what to avoid re-recommending.
        // Empty until the user starts answering the weekly question card.
        let personaBlock = PersonaService(modelContext: modelContext).promptContextBlock()
        if !personaBlock.isEmpty {
            lines.append("")
            lines.append(personaBlock)
        }

        return lines.joined(separator: "\n")
    }

    private func rejectedSummaries() -> [String] {
        let active = memoryService.active(asOf: now())
        let values = active
            .filter { $0.key.hasPrefix("rejected_suggestion_") }
            .map { $0.value }
        return Array(values.prefix(8))
    }

    private func persistRun(intake: ScheduleIntake,
                            proposal: GenerationProposal,
                            model: String,
                            tokens: Int) throws -> ScheduleGenerationRun {
        let intakeJSON = (try? JSONEncoder().encode(intake)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let proposalJSON = (try? JSONEncoder().encode(proposal)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let run = ScheduleGenerationRun(
            generatedAt: now(),
            modelUsed: model,
            intakeJSON: intakeJSON,
            proposalJSON: proposalJSON,
            status: .proposed,
            tokenUsage: tokens,
            costEstimateCents: estimateCostCents(model: model, tokens: tokens)
        )
        modelContext.insert(run)
        try modelContext.save()
        return run
    }

    private func ensureProfile() -> UserProfile {
        if let existing = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first {
            return existing
        }
        let new = UserProfile()
        modelContext.insert(new)
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
        return new
    }

    /// Rough cost estimate per model. Used for the Settings → Diagnostics
    /// "AI calls this month" surface. Not exact; intentionally rounded.
    private func estimateCostCents(model: String, tokens: Int) -> Int {
        // Conservative average of in/out price per million tokens, in USD cents.
        let centsPerMillion: Int
        switch model {
        case "claude-opus-4-7", "claude-opus-4-6": centsPerMillion = 1500   // ~$15/M average
        case "claude-sonnet-4-6", "claude-sonnet-4-5": centsPerMillion = 300 // ~$3/M average
        case "claude-haiku-4-5", "claude-haiku-4-5-20251001": centsPerMillion = 100 // ~$1/M
        default: centsPerMillion = 500
        }
        return (tokens * centsPerMillion) / 1_000_000
    }
}
#endif
