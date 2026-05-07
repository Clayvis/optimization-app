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
            let config = try ScheduleConfigLoader.load()
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
        guard let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first else {
            return .result(dialog: "No profile yet.")
        }
        do {
            let config = try ScheduleConfigLoader.load()
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
            let config = try ScheduleConfigLoader.load()
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
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let day = cal.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        let log: DailyLog = (try? context.fetch(descriptor))?.first ?? {
            let new = DailyLog(date: day)
            context.insert(new)
            return new
        }()
        switch module {
        case .japanese:    log.japaneseMinutes += minutes
        case .guitar:      log.guitarMinutes += minutes
        case .coursework:  log.courseworkMinutes += minutes
        }
        try? context.save()
        return .result(dialog: "Added \(minutes) minutes of \(module.rawValue).")
    }
}

enum LearningModuleOption: String, AppEnum {
    case japanese, guitar, coursework

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Module"
    static let caseDisplayRepresentations: [LearningModuleOption: DisplayRepresentation] = [
        .japanese:   "Japanese",
        .guitar:     "guitar",
        .coursework: "coursework"
    ]
}

// MARK: - Coach memory ("tell my coach...")

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
