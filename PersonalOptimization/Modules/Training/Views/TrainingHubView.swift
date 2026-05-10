import SwiftUI
import SwiftData

struct TrainingHubView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PrescribedWorkoutCard()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                InProgressSessionsSection()

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
                    CustomActivitiesQuickList()
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

/// User-defined activities surfaced inline under the typed sessions. Empty
/// state nudges the user to define their own.
private struct CustomActivitiesQuickList: View {
    @Query(sort: [SortDescriptor(\CustomActivityTemplate.createdAt, order: .forward)])
    private var templates: [CustomActivityTemplate]

    private var visible: [CustomActivityTemplate] {
        templates.filter { !$0.archived }
    }

    var body: some View {
        if visible.isEmpty {
            NavigationLink(destination: CustomActivitiesSettingsView()) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.app")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add your own activity").font(.body.weight(.semibold))
                        Text("Running, walking, HIIT, yoga, anything.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            ForEach(visible, id: \.persistentModelID) { template in
                NavigationLink(destination: CustomActivitySessionView(template: template)) {
                    HStack(spacing: 12) {
                        Image(systemName: template.systemImageName)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.body.weight(.semibold))
                            Text("\(template.defaultDurationMinutes) min default")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            NavigationLink(destination: CustomActivitiesSettingsView()) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.app")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 32)
                    Text("Manage activities")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// Banner above the start-a-session list showing any active session the user
/// can resume. Without this, leaving the screen mid-session leaves orphaned
/// rows (now resumable from the inner views, but invisible to the user from
/// the hub).
private struct InProgressSessionsSection: View {
    @Query private var lifts: [LiftSession]
    @Query private var bball: [BasketballSession]
    @Query private var swims: [SwimSession]

    private var activeLifts: [LiftSession] { lifts.filter { $0.durationMinutes == 0 } }
    private var activeBasketball: [BasketballSession] { bball.filter { $0.startTime == $0.endTime } }
    private var activeSwims: [SwimSession] { swims.filter { $0.durationMinutes == 0 } }

    private var hasAny: Bool { !activeLifts.isEmpty || !activeBasketball.isEmpty || !activeSwims.isEmpty }

    var body: some View {
        if hasAny {
            Section("In progress — tap to resume") {
                ForEach(activeLifts, id: \.persistentModelID) { session in
                    NavigationLink(destination: LiftSessionView(templateName: session.template)) {
                        resumeRow(icon: "figure.strengthtraining.traditional",
                                  title: session.template,
                                  detail: detail(for: session))
                    }
                }
                ForEach(activeBasketball, id: \.persistentModelID) { session in
                    NavigationLink(destination: BasketballSessionView()) {
                        resumeRow(icon: "basketball.fill",
                                  title: "Basketball",
                                  detail: "started \(formatTime(session.startTime))")
                    }
                }
                ForEach(activeSwims, id: \.persistentModelID) { session in
                    NavigationLink(destination: SwimSessionView()) {
                        resumeRow(icon: "figure.pool.swim",
                                  title: "Swim",
                                  detail: "started \(formatTime(session.date))")
                    }
                }
            }
        }
    }

    private func detail(for session: LiftSession) -> String {
        let exercises = session.exercises ?? []
        let sets = exercises.reduce(0) { $0 + ($1.sets ?? []).count }
        return "\(sets) set\(sets == 1 ? "" : "s") logged · started \(formatTime(session.date))"
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    @ViewBuilder
    private func resumeRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .foregroundStyle(.orange)
        }
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
