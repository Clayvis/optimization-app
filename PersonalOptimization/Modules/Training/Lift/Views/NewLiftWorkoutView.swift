import SwiftUI
import SwiftData

/// Start screen for lifting when workouts change day to day: build one as
/// you go, repeat a recent workout under its real name, or open today's
/// coach plan. Replaces the fixed "Lift A" / "My Workout" entry points.
struct NewLiftWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PrescribedWorkout.generatedAt, order: .reverse)])
    private var prescriptions: [PrescribedWorkout]

    @State private var name = ""
    @State private var recent: [LiftSession] = []
    @State private var loadError: String?

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? LiftService.freestyleName : trimmed
    }

    /// Today's coach lift plan while it is still open, matching the card's day rule.
    private var todaysLiftPlan: PrescribedWorkout? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let day = calendar.startOfDay(for: Date())
        return prescriptions.first { calendar.isDate($0.forDate, inSameDayAs: day) }
            .flatMap { [.liftA, .liftB].contains($0.workoutType) && $0.status != .completed ? $0 : nil }
    }

    var body: some View {
        List {
            if let loadError {
                ErrorBanner(message: loadError) { self.loadError = nil }
            }
            if let plan = todaysLiftPlan {
                Section("Today's coach plan") {
                    NavigationLink {
                        SuggestedWorkoutDestination(prescription: plan)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.creativeTitle.isEmpty ? plan.workoutType.displayName : plan.creativeTitle)
                                .font(.body.weight(.semibold))
                            if !plan.rationale.isEmpty {
                                Text(plan.rationale).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            Section {
                TextField("Name (optional)", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("lift.new.name")
                NavigationLink {
                    LiftSessionView(templateName: resolvedName, autoStart: true, freestyle: true)
                } label: {
                    Label("Start empty workout", systemImage: "play.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .accessibilityIdentifier("lift.new.start")
            } header: {
                Text("Build it as you go")
            } footer: {
                Text("Add exercises while you train. Ones you've logged before appear as quick picks, and their weights prefill from last time.")
            }
            if !recent.isEmpty {
                Section("Repeat a recent workout") {
                    ForEach(recent, id: \.persistentModelID) { session in
                        NavigationLink {
                            LiftSessionView(templateName: session.template, repeatOf: session)
                        } label: {
                            RecentWorkoutRow(session: session)
                        }
                    }
                }
            }
        }
        .navigationTitle("New workout")
        .scrollContentBackground(.hidden)
        .background(DojoBackground())
        .task { reload() }
    }

    private func reload() {
        do {
            recent = try LiftService(modelContext: modelContext, templatesFile: LiftTemplatesFile(version: 1, templates: []))
                .recentWorkouts(limit: 6)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// A finished workout: its own name, when it was, and what was in it.
struct RecentWorkoutRow: View {
    let session: LiftSession

    private var exerciseNames: [String] {
        (session.exercises ?? []).sorted { $0.orderIndex < $1.orderIndex }.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.template).font(.body.weight(.semibold))
                Spacer()
                Text(session.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(exerciseNames.prefix(4).joined(separator: ", ") + (exerciseNames.count > 4 ? " +\(exerciseNames.count - 4)" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
