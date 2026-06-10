import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    /// Persistence rung the app launched on. Defaults to `.full` so previews
    /// and any other callers compile unchanged; the app injects the real mode.
    var persistenceMode: PersistenceMode = .full

    /// Local-only sync banner is dismissible per launch.
    @State private var showSyncBanner: Bool = true

    var body: some View {
        switch persistenceMode {
        case .recovery(let reason):
            PersistenceRecoveryView(reason: reason)
        case .full, .localOnly:
            mainContent
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if let profile = profiles.first, profile.onboardingCompleted {
                tabRoot
            } else {
                OnboardingView()
            }
        }
        .overlay(alignment: .top) {
            if case .localOnly(let reason) = persistenceMode, showSyncBanner {
                ErrorBanner(message: reason) { showSyncBanner = false }
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        // Handoff receiver. When the paired watch starts a workout it
        // publishes an NSUserActivity via HandoffService; tapping the
        // continuation banner on the iPhone lock screen brings the app to
        // the foreground and fires onContinueUserActivity with the same
        // activity type. We rebroadcast as a Notification so downstream
        // tabs (Training, Learning) can route the user to the matching
        // session screen with the template pre-filled.
        .onContinueUserActivity(HandoffActivityType.lift.rawValue) { activity in
            postHandoffNotification(activity: activity)
        }
        .onContinueUserActivity(HandoffActivityType.basketball.rawValue) { activity in
            postHandoffNotification(activity: activity)
        }
        .onContinueUserActivity(HandoffActivityType.swim.rawValue) { activity in
            postHandoffNotification(activity: activity)
        }
        .onContinueUserActivity(HandoffActivityType.customActivity.rawValue) { activity in
            postHandoffNotification(activity: activity)
        }
        .onContinueUserActivity(HandoffActivityType.learning.rawValue) { activity in
            postHandoffNotification(activity: activity)
        }
    }

    private func postHandoffNotification(activity: NSUserActivity) {
        guard let payload = HandoffPayload(activityType: activity.activityType, userInfo: activity.userInfo) else { return }
        NotificationCenter.default.post(name: .handoffActivityContinued, object: payload)
    }

    @ViewBuilder
    private var tabRoot: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }
            FastingView()
                .tabItem {
                    Label("Fast", systemImage: "timer")
                }
            HydrationView()
                .tabItem {
                    Label("Water", systemImage: "drop.fill")
                }
            TrainingHubView()
                .tabItem {
                    Label("Train", systemImage: "figure.run")
                }
            LearningHubView()
                .tabItem {
                    Label("Learn", systemImage: "book.fill")
                }
            JourneyView()
                .tabItem {
                    Label("Journey", systemImage: "chart.line.uptrend.xyaxis")
                }
            BiomarkersView()
                .tabItem {
                    Label("Labs", systemImage: "testtube.2")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        // Global in-the-moment log confirmation banner (identity copy + haptic).
        .logFeedbackOverlay()
        // Dojo theme: kurenai (crimson) accent everywhere a control reads the
        // environment tint — tab items, buttons, toggles, links, pickers.
        .tint(Theme.kurenai)
    }

}

#Preview {
    RootView()
        .modelContainer(previewContainer)
}

@MainActor
private let previewContainer: ModelContainer = {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)  // MARK: try? justified - best-effort; failure logged inside the called function.
    return container
}()
