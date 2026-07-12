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
            DojoHubView()
                .tabItem {
                    Label("Dojo", systemImage: "torii.gate")
                }
        }
        // Global in-the-moment log confirmation banner (identity copy + haptic).
        .logFeedbackOverlay()
        // Dojo theme: kurenai (crimson) accent everywhere a control reads the
        // environment tint — tab items, buttons, toggles, links, pickers.
        .tint(Theme.kurenai)
    }

}

// MARK: - Dojo hub

/// Keeps the root tab bar to five predictable destinations. The previous
/// eight-tab layout was pushed into iOS's automatic "More" controller, which
/// hid core features behind a visually unrelated system list. The Dojo is a
/// deliberate home for the slower-cadence modules while Today, Fast, Water,
/// and Train remain one tap away.
private struct DojoHubView: View {
    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.m),
        GridItem(.flexible(), spacing: Theme.Space.m)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    dojoHeader

                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionEyebrow(title: "Practice halls", tint: Theme.kin)
                        LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                            dojoTile(
                                title: "Learning",
                                subtitle: "Language, guitar, music",
                                systemImage: "book.closed.fill",
                                tint: Theme.murasaki,
                                destination: LearningHubView(embedded: true)
                            )
                            dojoTile(
                                title: "Journey",
                                subtitle: "Trends, streaks, progress",
                                systemImage: "chart.line.uptrend.xyaxis",
                                tint: Theme.matcha,
                                destination: JourneyView(embedded: true)
                            )
                            dojoTile(
                                title: "Biomarkers",
                                subtitle: "Labs and health signals",
                                systemImage: "testtube.2",
                                tint: Theme.ai,
                                destination: BiomarkersView(embedded: true)
                            )
                            dojoTile(
                                title: "Settings",
                                subtitle: "Profile, schedule, devices",
                                systemImage: "gearshape.fill",
                                tint: Theme.textSecondary,
                                destination: SettingsView(embedded: true)
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("The Dojo")
            .background(DojoBackground())
        }
    }

    private var dojoHeader: some View {
        DojoCard(accent: Theme.kurenai) {
            HStack(spacing: Theme.Space.l) {
                ZStack {
                    Circle()
                        .fill(Theme.kurenai.opacity(0.14))
                    Image(systemName: "torii.gate")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Theme.kurenai)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Sharpen the whole system")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Review progress, practice skills, inspect health, and tune your protocol.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func dojoTile<Destination: View>(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        destination: Destination
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(tint.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
            .dojoCardSurface()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(DojoPressStyle())
        .accessibilityLabel("\(title). \(subtitle)")
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
