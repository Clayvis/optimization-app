import SwiftUI
import SwiftData

/// Settings → About. Surfaces enough context for either user (Clay, wife) to
/// self-diagnose during the 30-day TestFlight test: app version + build,
/// schema version, days since first launch, total session count across all
/// activity types. No links, no third-party SDKs.
@MainActor
struct AboutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    private var schemaVersion: String {
        let v = AppSchema.current.versionIdentifier
        return "\(v.major).\(v.minor).\(v.patch)"
    }

    private var daysSinceFirstLaunch: Int {
        // FirstLaunchTracker writes the install timestamp to UserDefaults the
        // very first time the app launches. We read it here for an accurate
        // "days since" reading even before the user logs anything.
        let firstLaunch = FirstLaunchTracker.shared.firstLaunchAt
        let interval = Date().timeIntervalSince(firstLaunch)
        return max(0, Int(interval / 86_400))
    }

    private var totalSessions: Int {
        // MARK: try? justified - best-effort; nil/empty result is acceptable at this call site.
        let lifts = (try? modelContext.fetch(FetchDescriptor<LiftSession>()))?.count ?? 0
        // MARK: try? justified - best-effort; nil/empty result is acceptable at this call site.
        let bball = (try? modelContext.fetch(FetchDescriptor<BasketballSession>()))?.count ?? 0
        // MARK: try? justified - best-effort; nil/empty result is acceptable at this call site.
        let swim = (try? modelContext.fetch(FetchDescriptor<SwimSession>()))?.count ?? 0
        // MARK: try? justified - best-effort; nil/empty result is acceptable at this call site.
        let custom = (try? modelContext.fetch(FetchDescriptor<CustomActivitySession>()))?.count ?? 0
        return lifts + bball + swim + custom
    }

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Version", value: "\(appVersion) (\(appBuild))")
                LabeledContent("Schema", value: schemaVersion)
            }
            Section("Usage") {
                LabeledContent("Days since first launch", value: "\(daysSinceFirstLaunch)")
                LabeledContent("Total sessions logged", value: "\(totalSessions)")
            }
            Section {
                Text("Data lives in your private iCloud. Nothing is shared with anyone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
    }
}
