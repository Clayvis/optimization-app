import AppIntents
import Foundation
import SwiftData

/// Voice + Siri quick-log intents (Opp 8). Shipped to bring logging
/// friction below 5 seconds (research: <5s logging produces 3-5x more daily
/// logs). Each intent uses the shared ModelContainerWrapper so it works
/// without the full app environment.

// MARK: - Hydration

struct LogHydrationIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"
    static let description = IntentDescription(
        "Logs an amount of water (or a beverage) into today's hydration ledger."
    )

    @Parameter(title: "Amount in ounces", default: 16)
    var amountOz: Double

    @Parameter(title: "Beverage", default: .water)
    var beverage: BeverageIntentOption

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amountOz) oz of \(\.$beverage)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let wrapper = ModelContainerWrapper.shared else {
            return .result(dialog: "Couldn't open the database.")
        }
        do {
            let config = try ScheduleConfigLoader.loadCached()
            let service = HydrationService(modelContext: wrapper.mainContext,
                                           targets: config.hydrationTargetsOz)
            _ = try service.logBeverage(amountOz: amountOz, beverageType: beverage.toBeverageType())
            return .result(dialog: "Logged \(Int(amountOz)) ounces.")
        } catch {
            return .result(dialog: "Logging failed: \(error.localizedDescription)")
        }
    }
}

enum BeverageIntentOption: String, AppEnum {
    case water, coffee, tea, electrolyte, other

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Beverage"
    static let caseDisplayRepresentations: [BeverageIntentOption: DisplayRepresentation] = [
        .water:       "water",
        .coffee:      "coffee",
        .tea:         "tea",
        .electrolyte: "electrolyte",
        .other:       "other"
    ]

    func toBeverageType() -> BeverageType {
        switch self {
        case .water:       return .water
        case .coffee:      return .coffee
        case .tea:         return .tea
        case .electrolyte: return .electrolyte
        case .other:       return .other
        }
    }
}

// MARK: - Fasting

struct StartFastIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a fast"
    static let description = IntentDescription("Begins a manual fast right now.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let wrapper = ModelContainerWrapper.shared else {
            return .result(dialog: "Couldn't open the database.")
        }
        let context = wrapper.mainContext
        guard let profile = context.fetchFirstOrNil(FetchDescriptor<UserProfile>()) else {
            return .result(dialog: "No profile yet.")
        }
        do {
            let config = try ScheduleConfigLoader.loadCached()
            let service = FastingService(modelContext: context, defaults: config.fastingDefaults)
            _ = try service.startManualFast(profile: profile)
            return .result(dialog: "Fast started.")
        } catch FastingError.alreadyFasting {
            return .result(dialog: "A fast is already in progress.")
        } catch {
            return .result(dialog: "Couldn't start the fast: \(error.localizedDescription)")
        }
    }
}

struct EndFastIntent: AppIntent {
    static let title: LocalizedStringResource = "End the current fast"
    static let description = IntentDescription("Closes the open fasting window right now.")

    @Parameter(title: "Optional note", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("End fast with note \(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let wrapper = ModelContainerWrapper.shared else {
            return .result(dialog: "Couldn't open the database.")
        }
        let context = wrapper.mainContext
        do {
            let config = try ScheduleConfigLoader.loadCached()
            let service = FastingService(modelContext: context, defaults: config.fastingDefaults)
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try service.endManualFast(reason: trimmed.isEmpty ? nil : trimmed)
            return .result(dialog: "Fast ended.")
        } catch FastingError.noActiveFast {
            return .result(dialog: "No fast in progress.")
        } catch {
            return .result(dialog: "Couldn't end the fast: \(error.localizedDescription)")
        }
    }
}

// MARK: - Learning

struct LogLearningIntent: AppIntent {
    static let title: LocalizedStringResource = "Log learning minutes"
    static let description = IntentDescription("Adds minutes of focused learning to today's log.")

    @Parameter(title: "Module", default: .japanese)
    var module: LearningModuleOption

    @Parameter(title: "Minutes", default: 25)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$minutes) minutes of \(\.$module)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let wrapper = ModelContainerWrapper.shared else {
            return .result(dialog: "Couldn't open the database.")
        }
        let context = wrapper.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = UserCalendar.timezone(modelContext: context)
        let log = DailyLogStore(modelContext: context, calendar: cal).upsertToday()
        switch module {
        case .japanese:    log.japaneseMinutes += minutes
        case .guitar:      log.guitarMinutes += minutes
        case .coursework:  log.courseworkMinutes += minutes
        case .music:       log.musicMinutes += minutes
        }
        try? context.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
        return .result(dialog: "Added \(minutes) minutes of \(module.rawValue).")
    }
}

enum LearningModuleOption: String, AppEnum {
    case japanese, guitar, coursework, music

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Module"
    static let caseDisplayRepresentations: [LearningModuleOption: DisplayRepresentation] = [
        .japanese:   "Japanese",
        .guitar:     "guitar",
        .coursework: "coursework",
        .music:      "music"
    ]
}

// MARK: - Coach memory ("tell my coach...")

// iOS-only intent. The Coach memory module isn't built into the watch
// target, so this intent compiles only for the phone. The watch surface
// for "tell my coach" lives in the watch app's text-entry view instead.
#if os(iOS)
struct TellCoachIntent: AppIntent {
    static let title: LocalizedStringResource = "Tell my coach"
    static let description = IntentDescription("Saves a free-text note the Coach will reference for the next 7 days.")

    @Parameter(title: "Note")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Tell coach \(\.$note)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let wrapper = ModelContainerWrapper.shared else {
            return .result(dialog: "Couldn't open the database.")
        }
        do {
            let service = CoachMemoryService(modelContext: wrapper.mainContext)
            _ = try service.add(value: note, importance: 4, expiresIn: 7)
            return .result(dialog: "Saved. The Coach will hold that for a week.")
        } catch {
            return .result(dialog: "Couldn't save: \(error.localizedDescription)")
        }
    }
}
#endif

// MARK: - Workout

/// Zero-friction "I just worked out" log. Credits the day's workout without the
/// timer-based session UI, for the common case where the user trained but did
/// not run an in-app session (and the Watch/HealthKit import has not landed yet).
/// Deduped naturally: an imported HealthKit workout and this manual log both
/// create a WorkoutEvent for the day, and the streak counts the day, not rows.
struct LogWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a workout"
    static let description = IntentDescription("Records that you completed a workout today. No timer needed.")

    @Parameter(title: "Type", default: .lift)
    var type: WorkoutTypeOption

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$type) workout")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let wrapper = ModelContainerWrapper.shared else {
            return .result(dialog: "Couldn't open the database.")
        }
        let context = wrapper.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = UserCalendar.timezone(modelContext: context)
        let day = cal.startOfDay(for: Date())
        context.insert(WorkoutEvent(date: day, completed: true, source: type.toSource()))
        CompletionHistoryWriter.record(domain: .workout, at: Date(), modelContext: context)
        // MARK: try? save() is best-effort. CompletionHistoryWriter already saved; failures surface via os_log.
        try? context.save()
        NotificationCenter.default.post(name: .dailyLogsRecomputed, object: nil)
        return .result(dialog: "\(IdentityCopy.workoutLogged)")
    }
}

enum WorkoutTypeOption: String, AppEnum {
    case lift, basketball, swim, cardio

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workout type"
    static let caseDisplayRepresentations: [WorkoutTypeOption: DisplayRepresentation] = [
        .lift:       "lift",
        .basketball: "basketball",
        .swim:       "swim",
        .cardio:     "cardio"
    ]

    func toSource() -> WorkoutEventSource {
        switch self {
        case .lift:       return .lift
        case .basketball: return .basketball
        case .swim:       return .swim
        case .cardio:     return .custom
        }
    }
}
