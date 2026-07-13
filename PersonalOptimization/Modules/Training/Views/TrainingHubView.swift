import SwiftUI
import SwiftData
import HealthKit

/// Training hub, dojo-styled. Card stack instead of a grouped list:
/// prescription on top, a resume banner when a session is live, a
/// week-at-a-glance hero, a tile grid to start sessions, and today's log.
struct TrainingHubView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    PrescribedWorkoutCard()
                    InProgressBanner()
                    WeekAtAGlanceCard()
                    StartSessionGrid()
                    TodaysSessionsCard()
                }
                .padding()
            }
            .navigationTitle("Training")
            .scrollContentBackground(.hidden)
            .background(DojoBackground())
        }
    }
}

// MARK: - Resume banner

/// Active session the user can jump back into. Without this, leaving the
/// screen mid-session leaves orphaned rows (resumable from the inner views,
/// but invisible from the hub). Crimson accent: this is the screen's one
/// urgent affordance.
private struct InProgressBanner: View {
    @Query private var lifts: [LiftSession]
    @Query private var bball: [BasketballSession]
    @Query private var swims: [SwimSession]

    private var activeLifts: [LiftSession] { lifts.filter { $0.durationMinutes == 0 } }
    private var activeBasketball: [BasketballSession] { bball.filter { $0.startTime == $0.endTime } }
    private var activeSwims: [SwimSession] { swims.filter { $0.durationMinutes == 0 } }

    private var hasAny: Bool { !activeLifts.isEmpty || !activeBasketball.isEmpty || !activeSwims.isEmpty }

    var body: some View {
        if hasAny {
            DojoCard(accent: Theme.kurenai, padding: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionEyebrow(title: "In progress")
                    ForEach(activeLifts, id: \.persistentModelID) { session in
                        NavigationLink(destination: LiftSessionView(templateName: session.template, autoStart: true)) {
                            resumeRow(icon: "figure.strengthtraining.traditional",
                                      title: session.template,
                                      detail: detail(for: session))
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(activeBasketball, id: \.persistentModelID) { session in
                        NavigationLink(destination: BasketballSessionView()) {
                            resumeRow(icon: "basketball.fill",
                                      title: "Basketball",
                                      detail: "started \(formatTime(session.startTime))")
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(activeSwims, id: \.persistentModelID) { session in
                        NavigationLink(destination: SwimSessionView()) {
                            resumeRow(icon: "figure.pool.swim",
                                      title: "Swim",
                                      detail: "started \(formatTime(session.date))")
                        }
                        .buttonStyle(.plain)
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

    @ViewBuilder
    private func resumeRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.kurenai)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.kurenai)
        }
        .padding(.vertical, Theme.Space.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resume \(title), \(detail)")
    }
}

// MARK: - Week at a glance

/// Master metric for the tab: sessions completed this week, with a 7-day dot
/// strip and stat chips. Counts only finished sessions; no invented targets,
/// the dots just show which days actually had work.
private struct WeekAtAGlanceCard: View {
    @Query private var lifts: [LiftSession]
    @Query private var bball: [BasketballSession]
    @Query private var swims: [SwimSession]
    @Query private var customs: [CustomActivitySession]

    var body: some View {
        let cal = Calendar.current
        let week = cal.dateInterval(of: .weekOfYear, for: Date())
            ?? DateInterval(start: cal.startOfDay(for: Date()), duration: 7 * 86_400)

        let weekLifts = lifts.filter { week.contains($0.date) && $0.durationMinutes > 0 }
        let weekBball = bball.filter { week.contains($0.date) && $0.endTime > $0.startTime }
        let weekSwims = swims.filter { week.contains($0.date) && $0.durationMinutes > 0 }
        let weekCustoms = customs.filter { week.contains($0.date) }

        let sessionCount = weekLifts.count + weekBball.count + weekSwims.count + weekCustoms.count
        let minutes = weekLifts.reduce(0) { $0 + $1.durationMinutes }
            + weekBball.reduce(0) { $0 + Int($1.endTime.timeIntervalSince($1.startTime) / 60) }
            + weekSwims.reduce(0) { $0 + $1.durationMinutes }
            + weekCustoms.reduce(0) { $0 + $1.durationMinutes }
        let volumeLbs = weekLifts.reduce(0.0) { $0 + $1.totalVolumeLbs }
        let meters = weekSwims.reduce(0.0) { $0 + $1.totalMeters }

        let allDates = weekLifts.map(\.date) + weekBball.map(\.date)
            + weekSwims.map(\.date) + weekCustoms.map(\.date)
        let trainedDays = Set(allDates.compactMap {
            cal.dateComponents([.day], from: week.start, to: cal.startOfDay(for: $0)).day
        })

        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionEyebrow(title: "This week", tint: Theme.matcha)

            HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
                Text("\(sessionCount)")
                    .font(Theme.numeral(44))
                    .foregroundStyle(Theme.textPrimary)
                Text("session\(sessionCount == 1 ? "" : "s")")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            WeekDayDots(trainedDays: trainedDays, weekStart: week.start)

            if minutes > 0 {
                HStack(spacing: Theme.Space.s) {
                    StatChip(systemImage: "timer", text: "\(minutes) min")
                    if volumeLbs > 0 {
                        StatChip(systemImage: "dumbbell.fill",
                                 text: "\(Int(volumeLbs)) lbs",
                                 tint: Theme.kurenai)
                    }
                    if meters > 0 {
                        StatChip(systemImage: "figure.pool.swim",
                                 text: "\(Int(meters)) m",
                                 tint: Theme.ai)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
    }
}

/// Seven dots, Mon..Sun per the user's calendar, filled jade for days with at
/// least one completed session, crimson outline on today.
private struct WeekDayDots: View {
    let trainedDays: Set<Int>
    let weekStart: Date

    var body: some View {
        let cal = Calendar.current
        let todayIndex = cal.dateComponents([.day], from: weekStart,
                                            to: cal.startOfDay(for: Date())).day ?? -1

        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { offset in
                let day = cal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                VStack(spacing: Theme.Space.xs) {
                    Circle()
                        .fill(trainedDays.contains(offset) ? Theme.matcha : Theme.inkSunken)
                        .overlay(
                            Circle().stroke(offset == todayIndex ? Theme.kurenai : Theme.hairline,
                                            lineWidth: offset == todayIndex ? 1.5 : 1)
                        )
                        .frame(width: 12, height: 12)
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(offset == todayIndex ? Theme.textPrimary : Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trained \(trainedDays.count) of 7 days this week")
    }
}

// MARK: - Start a session

/// Two-column tile grid. Each discipline keeps its pigment: crimson for iron,
/// gold for court, indigo for water, jade for everything the user defines.
/// Tiles open the activity's prep screen (explicit Start Session inside),
/// never auto-start, and show the last completed workout's HealthKit recap.
private struct StartSessionGrid: View {
    @Query(sort: [SortDescriptor(\CustomActivityTemplate.createdAt, order: .forward)])
    private var templates: [CustomActivityTemplate]

    /// Latest completed workout recap per tile, keyed by tile identity.
    @State private var recaps: [String: WorkoutRecap] = [:]

    private var visible: [CustomActivityTemplate] {
        templates.filter { !$0.archived }
    }

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.m),
        GridItem(.flexible(), spacing: Theme.Space.m)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionEyebrow(title: "Start a session")
            LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                ActivityTile(icon: "figure.strengthtraining.traditional",
                             title: "Lift A",
                             subtitle: "legs, push, pull",
                             tint: Theme.kurenai,
                             recap: recaps["lift"]?.line) {
                    LiftSessionView(templateName: "Lift A")
                }
                ActivityTile(icon: "figure.strengthtraining.functional",
                             title: "My Workout",
                             subtitle: "your custom lift",
                             tint: Theme.kurenai,
                             recap: recaps["lift"]?.line) {
                    LiftSessionView(templateName: CustomLiftTemplateStore.templateName)
                }
                ActivityTile(icon: "basketball.fill",
                             title: "Basketball",
                             subtitle: "DeepWater Elite",
                             tint: Theme.kin,
                             recap: recaps["basketball"]?.line) {
                    BasketballSessionView()
                }
                ActivityTile(icon: "figure.pool.swim",
                             title: "Swim",
                             subtitle: "McTureous, 25m",
                             tint: Theme.ai,
                             recap: recaps["swim"]?.line) {
                    SwimSessionView()
                }
                ForEach(visible, id: \.persistentModelID) { template in
                    ActivityTile(icon: template.systemImageName,
                                 title: template.name,
                                 subtitle: "\(template.defaultDurationMinutes) min default",
                                 tint: Theme.matcha,
                                 recap: recaps["custom:\(template.name)"]?.line) {
                        CustomActivitySessionView(template: template)
                    }
                }
                ActivityTile(icon: "plus.app",
                             title: visible.isEmpty ? "Add activity" : "Manage",
                             subtitle: visible.isEmpty
                                ? "Run, HIIT, yoga, anything"
                                : "Edit your activities",
                             tint: Theme.textSecondary) {
                    CustomActivitiesSettingsView()
                }
            }
        }
        .task { await loadRecaps() }
    }

    /// One workouts fetch over the trailing 30 days, distributed to tiles by
    /// activity type. HealthKit is the source so watch-recorded and
    /// third-party workouts count too. Absence of data just hides the line.
    /// Plain loops throughout: closure-based matching tripped Swift 6 region
    /// analysis ("sending closure risks data races") under Release WMO.
    private func loadRecaps() async {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        guard let workouts = try? await LiveHealthKitService.shared.fetchWorkouts(
            in: DateInterval(start: start, end: now)
        ) else { return } // MARK: try? justified - recap line is decorative; unauthorized/no-data hides it.

        var customTypes: [String: HKWorkoutActivityType] = [:]
        for template in visible {
            let type = WorkoutMetrics.hkActivityType(forTemplateNamed: template.name)
            if type != .other {
                customTypes["custom:\(template.name)"] = type
            }
        }

        // fetchWorkouts sorts newest-first; keep the first hit per tile key.
        var next: [String: WorkoutRecap] = [:]
        for workout in workouts {
            let type = workout.workoutActivityType
            var keys: [String] = []
            if type == .functionalStrengthTraining || type == .traditionalStrengthTraining {
                keys.append("lift")
            }
            if type == .basketball { keys.append("basketball") }
            if type == .swimming { keys.append("swim") }
            for (key, customType) in customTypes where customType == type {
                keys.append(key)
            }
            for key in keys where next[key] == nil {
                next[key] = WorkoutRecap.from(workout: workout)
            }
        }
        recaps = next
    }
}

/// One tappable tile: tinted icon plate, title, subtitle, and the last
/// session's HealthKit recap when one exists. Lacquer surface.
private struct ActivityTile<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var recap: String?
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(tint.opacity(0.14))
                    )
                Spacer(minLength: Theme.Space.xs)
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if let recap {
                    Text(recap)
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .dojoCardSurface()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(DojoPressStyle())
        .accessibilityLabel(recap == nil ? "\(title). \(subtitle)" : "\(title). \(subtitle). Last session \(recap ?? "")")
    }
}

// MARK: - Today's log

private struct TodaysSessionsCard: View {
    @Query private var lifts: [LiftSession]
    @Query private var bball: [BasketballSession]
    @Query private var swims: [SwimSession]
    @Query private var customs: [CustomActivitySession]

    private struct Row: Identifiable {
        let id: PersistentIdentifier
        let icon: String
        let tint: Color
        let title: String
        let detail: String
        let date: Date
    }

    private var rows: [Row] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [Row] = []

        for s in lifts where cal.isDate(s.date, inSameDayAs: today) && s.durationMinutes > 0 {
            out.append(Row(id: s.persistentModelID,
                           icon: "dumbbell.fill",
                           tint: Theme.kurenai,
                           title: s.template,
                           detail: "\(Int(s.totalVolumeLbs)) lbs · \(s.durationMinutes) min",
                           date: s.date))
        }
        for s in bball where cal.isDate(s.date, inSameDayAs: today) && s.endTime > s.startTime {
            let mins = Int(s.endTime.timeIntervalSince(s.startTime) / 60)
            out.append(Row(id: s.persistentModelID,
                           icon: "basketball.fill",
                           tint: Theme.kin,
                           title: "Basketball",
                           detail: "\(mins) min · achilles \(s.achillesPostScore.map(String.init) ?? "n/a")",
                           date: s.date))
        }
        for s in swims where cal.isDate(s.date, inSameDayAs: today) && s.durationMinutes > 0 {
            out.append(Row(id: s.persistentModelID,
                           icon: "figure.pool.swim",
                           tint: Theme.ai,
                           title: "Swim",
                           detail: "\(Int(s.totalMeters)) m · \(s.durationMinutes) min",
                           date: s.date))
        }
        for s in customs where cal.isDate(s.date, inSameDayAs: today) {
            var detail = "\(s.durationMinutes) min"
            if let meters = s.distanceMeters, meters > 0 {
                detail = String(format: "%.1f km · ", meters / 1000) + detail
            }
            out.append(Row(id: s.persistentModelID,
                           icon: "figure.run",
                           tint: Theme.matcha,
                           title: s.templateName,
                           detail: detail,
                           date: s.date))
        }
        return out.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionEyebrow(title: "Today")
            if rows.isEmpty {
                Text("No sessions yet today.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: Theme.Space.m) {
                        Image(systemName: row.icon)
                            .font(.title3)
                            .foregroundStyle(row.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(row.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.matcha)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .dojoCardSurface()
    }
}

// MARK: - Shared

private func formatTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.timeZone = TimeZone.current
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

#Preview {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])

    let context = container.mainContext
    let lift = LiftSession(date: Date(), template: "Lift A")
    lift.totalVolumeLbs = 12450
    lift.durationMinutes = 52
    context.insert(lift)
    let swim = SwimSession(date: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date())
    swim.totalMeters = 1000
    swim.durationMinutes = 30
    context.insert(swim)
    context.insert(CustomActivityTemplate(name: "Rucking", systemImageName: "figure.hiking", defaultDurationMinutes: 45))

    return TrainingHubView().modelContainer(container)
}
