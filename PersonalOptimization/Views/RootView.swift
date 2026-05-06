import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }
            HistoryStubView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

private struct HistoryStubView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "History",
                systemImage: "clock.arrow.circlepath",
                description: Text("Daily logs, training, and biomarker trends arrive in later milestones.")
            )
            .navigationTitle("History")
        }
    }
}

#Preview {
    RootView()
        .modelContainer(previewContainer)
}

@MainActor
private let previewContainer: ModelContainer = {
    let schema = Schema(versionedSchema: SchemaV1.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    try? ScheduleSeed.seedIfNeeded(modelContext: container.mainContext)
    return container
}()
