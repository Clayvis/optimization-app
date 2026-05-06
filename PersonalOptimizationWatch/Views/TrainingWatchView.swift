import SwiftUI
import SwiftData
import WatchKit

struct TrainingWatchView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    LiftWatchView(templateName: "Lift A")
                } label: {
                    rowLabel(icon: "figure.strengthtraining.traditional", title: "Lift A")
                }
                NavigationLink {
                    LiftWatchView(templateName: "Lift B")
                } label: {
                    rowLabel(icon: "figure.strengthtraining.functional", title: "Lift B")
                }
                NavigationLink {
                    BasketballWatchView()
                } label: {
                    rowLabel(icon: "basketball.fill", title: "Basketball")
                }
                NavigationLink {
                    SwimWatchView()
                } label: {
                    rowLabel(icon: "figure.pool.swim", title: "Swim")
                }
            }
            .navigationTitle("Train")
        }
    }

    private func rowLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text(title).font(.body.weight(.semibold))
        }
        .frame(height: 36)
    }
}
