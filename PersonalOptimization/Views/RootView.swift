import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first, profile.onboardingCompleted {
                tabRoot
            } else {
                OnboardingView()
            }
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
}

#Preview {
    RootView()
        .modelContainer(previewContainer)
}

@MainActor
private let previewContainer: ModelContainer = {
    let schema = Schema(versionedSchema: SchemaV7.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
    return container
}()
