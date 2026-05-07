import AppIntents
import Foundation
import SwiftData

struct StartCurrentBlockWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start workout for current block"
    static let description = IntentDescription("Reads the current scheduled block and starts the matching workout (Lift, Basketball, or Swim).")

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let module = WorkoutIntentRouter.currentBlockModule()
        let summary = module.map { "Starting \($0.replacingOccurrences(of: "_", with: " "))" } ?? "No workout block right now"
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

/// Resolves the current ScheduleBlock module so intents and watch UI agree.
@MainActor
enum WorkoutIntentRouter {
    static func currentBlockModule(now: Date = Date()) -> String? {
        guard let wrapper = ModelContainerWrapper.shared else { return nil }
        let service = ScheduleService(modelContext: wrapper.mainContext)
        return service.currentBlock(at: now)?.module
    }
}

/// Holds a process-wide ModelContainer so AppIntents can invoke services without the
/// full app environment. Lazily initialised and CloudKit-backed identically to the
/// host apps.
@MainActor
final class ModelContainerWrapper {
    static let shared: ModelContainerWrapper? = ModelContainerWrapper()

    let container: ModelContainer

    private init?() {
        let schema = Schema(versionedSchema: SchemaV6.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.rawlins.PersonalOptimization")
        )
        do {
            self.container = try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            return nil
        }
    }

    var mainContext: ModelContext { container.mainContext }
}
