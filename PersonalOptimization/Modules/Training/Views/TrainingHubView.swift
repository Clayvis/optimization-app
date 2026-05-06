import SwiftUI
import SwiftData

struct TrainingHubView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                Section("Start a session") {
                    NavigationLink(destination: LiftSessionView(templateName: "Lift A")) {
                        startRow(icon: "figure.strengthtraining.traditional", title: "Lift A", subtitle: "legs, push, pull")
                    }
                    NavigationLink(destination: LiftSessionView(templateName: "Lift B")) {
                        startRow(icon: "figure.strengthtraining.functional", title: "Lift B", subtitle: "variation")
                    }
                    NavigationLink(destination: BasketballSessionView()) {
                        startRow(icon: "basketball.fill", title: "Basketball", subtitle: "DeepWater Elite")
                    }
                    NavigationLink(destination: SwimSessionView()) {
                        startRow(icon: "figure.pool.swim", title: "Swim", subtitle: "McTureous, 25m")
                    }
                }

                Section("Today") {
                    TodaysSessionsList()
                }
            }
            .navigationTitle("Training")
        }
    }

    @ViewBuilder
    private func startRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct TodaysSessionsList: View {
    @Query private var lifts: [LiftSession]
    @Query private var bball: [BasketballSession]
    @Query private var swims: [SwimSession]

    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let liftsToday = lifts.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
        let bballToday = bball.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
        let swimsToday = swims.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }

        if liftsToday.isEmpty && bballToday.isEmpty && swimsToday.isEmpty {
            Text("No sessions yet today.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(liftsToday, id: \.persistentModelID) { session in
                summaryRow(icon: "dumbbell.fill",
                          title: session.template,
                          detail: "\(Int(session.totalVolumeLbs)) lbs · \(session.durationMinutes) min")
            }
            ForEach(bballToday, id: \.persistentModelID) { session in
                let mins = Int(session.endTime.timeIntervalSince(session.startTime) / 60)
                summaryRow(icon: "basketball.fill",
                          title: "Basketball",
                          detail: "\(mins) min · achilles \(session.achillesPostScore.map(String.init) ?? "—")")
            }
            ForEach(swimsToday, id: \.persistentModelID) { session in
                summaryRow(icon: "figure.pool.swim",
                          title: "Swim",
                          detail: "\(Int(session.totalMeters)) m · \(session.durationMinutes) min")
            }
        }
    }

    @ViewBuilder
    private func summaryRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
