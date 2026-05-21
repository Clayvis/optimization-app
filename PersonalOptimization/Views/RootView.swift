import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var showTravelPrompt: Bool = false

    var body: some View {
        Group {
            if let profile = profiles.first, profile.onboardingCompleted {
                tabRoot
            } else {
                OnboardingView()
            }
        }
        .onAppear { checkTravelPrompt() }
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
        try? modelContext.save()
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
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
    return container
}()
