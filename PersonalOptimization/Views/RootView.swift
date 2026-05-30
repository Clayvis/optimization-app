import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var showTravelPrompt: Bool = false

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
        .onAppear { checkTravelPrompt() }
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
        .alert("Travel mode?", isPresented: $showTravelPrompt, presenting: profiles.first) { profile in
            Button("Follow my device") {
                profile.travelModeFollowsDevice = true
                markTravelPromptShown()
            }
            Button("Stay pinned to \(profile.timezone)", role: .cancel) {
                profile.travelModeFollowsDevice = false
                markTravelPromptShown()
            }
        } message: { profile in
            Text("You're not in \(profile.timezone) right now. Should the app follow your device's time zone for day boundaries and streak rollovers? You can change this anytime in Settings.")
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
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }

    /// One-shot prompt: if the device's tz differs from the profile's pinned
    /// tz and the user hasn't already made a travel-mode choice, ask them.
    /// Gated by a UserDefaults flag so we never nag a second time.
    private func checkTravelPrompt() {
        guard let profile = profiles.first, profile.onboardingCompleted else { return }
        guard !UserDefaults.standard.bool(forKey: Self.travelPromptKey) else { return }
        guard !profile.travelModeFollowsDevice else { return }
        let deviceTz = TimeZone.current.identifier
        guard deviceTz != profile.timezone else { return }
        showTravelPrompt = true
    }

    private func markTravelPromptShown() {
        UserDefaults.standard.set(true, forKey: Self.travelPromptKey)
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
    }

    private static let travelPromptKey = "TravelModePrompt.v1.shown"
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
