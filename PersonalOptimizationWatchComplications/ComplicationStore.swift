import Foundation
import SwiftData

/// Process-lifetime cache for the complications' read-only `ModelContainer`.
///
/// WidgetKit builds each timeline by calling a provider's `makeEntry` once per
/// stride entry (up to 73 for the fasting countdown, 25 for hydration/current
/// block, 13 for goal/mascot). Opening a fresh CloudKit-mirrored container on
/// every entry meant dozens of store opens per refresh — measurable watch
/// battery drain. WidgetKit runs each timeline build in a short-lived process,
/// so one static cache collapses those N opens into a single open for the life
/// of that process, then is torn down with it. Safe: the providers only read.
@MainActor
enum ComplicationStore {
    private static var cached: ModelContainer?

    /// The shared container, opened at most once per process. Returns nil if the
    /// store can't open; callers fall back to a placeholder entry.
    static func container() -> ModelContainer? {
        if let cached { return cached }
        let schema = AppSchema.schema()
        // Open the SAME App-Group store the watch app writes to so glances
        // reflect the latest local data instead of a separate CloudKit sandbox.
        let storeURL = AppGroupContainer.storeURL()
            ?? URL.applicationSupportDirectory.appending(path: "default.store")
        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .private("iCloud.com.rawlins.PersonalOptimization")
        )
        let container = try? ModelContainer(
            for: schema,
            migrationPlan: AppSchema.migrationPlan,
            configurations: [config]
        )
        cached = container
        return container
    }
}
