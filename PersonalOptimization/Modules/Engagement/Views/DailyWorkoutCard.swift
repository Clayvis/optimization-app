import SwiftUI
import SwiftData

/// The daily loop: see real progress, choose a manageable session, earn a win.
/// No account, API key, schedule, or manual Health re-entry is required.
@MainActor
struct DailyWorkoutCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<WorkoutEvent> { $0.completed }) private var events: [WorkoutEvent]
    @Query(filter: #Predicate<CustomActivityTemplate> { !$0.archived }, sort: \CustomActivityTemplate.createdAt)
    private var templates: [CustomActivityTemplate]
    @Query private var logs: [DailyLog]
    @Query private var lifts: [LiftSession]
    @Query private var swims: [SwimSession]
    @Query private var basketball: [BasketballSession]
    @Query private var custom: [CustomActivitySession]
    @AppStorage("dailyWorkout.goalMinutes") private var goalMinutes = 10
    @AppStorage("dailyWorkout.weeklyGoal") private var weeklyGoal = 3
    @AppStorage("dailyWorkout.activityName") private var activityName = "Walking"
    @State private var errorMessage: String?
    @State private var recovery: RecoveryRecommendation = .normal
    let now: Date

    init(now: Date) {
        self.now = now
        let day = Calendar.current.startOfDay(for: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? now
        // Include yesterday's starts to clip overnight sessions at midnight.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        _logs = Query(filter: #Predicate<DailyLog> { $0.date >= day && $0.date < tomorrow && $0.supersededAt == nil })
        _lifts = Query(filter: #Predicate<LiftSession> { $0.date >= yesterday && $0.date < tomorrow && $0.durationMinutes > 0 })
        _swims = Query(filter: #Predicate<SwimSession> { $0.date >= yesterday && $0.date < tomorrow && $0.durationMinutes > 0 })
        _basketball = Query(filter: #Predicate<BasketballSession> { $0.date >= yesterday && $0.date < tomorrow })
        _custom = Query(filter: #Predicate<CustomActivitySession> { $0.date >= yesterday && $0.date < tomorrow && $0.durationMinutes > 0 })
    }

    private var calendar: Calendar { UserCalendar.current(modelContext: modelContext) }
    private var todayLog: DailyLog? { logs.first }
    private var resting: Bool {
        (todayLog?.metadata("dailyWorkout.restDay", as: Bool.self) ?? false)
            || (profiles.first?.sickDayActiveUntil ?? .distantPast) >= now
    }
    private var recommendedRest: Bool { resting || recovery == .rest }
    private var targetMinutes: Int { recovery == .downgrade ? min(5, goalMinutes) : goalMinutes }
    private var selectedTemplate: CustomActivityTemplate? {
        templates.first { $0.name == activityName } ?? templates.first { $0.name == "Walking" } ?? templates.first
    }

    private var progress: DailyWorkoutProgress {
        var intervals: [DateInterval] = []
        for session in lifts { intervals.append(interval(start: session.date, minutes: session.durationMinutes)) }
        for session in swims { intervals.append(interval(start: session.date, minutes: session.durationMinutes)) }
        for session in custom { intervals.append(interval(start: session.date, minutes: session.durationMinutes)) }
        for session in basketball where session.endTime > session.startTime {
            intervals.append(DateInterval(start: session.startTime, end: session.endTime))
        }
        return DailyWorkoutProgress(
            workoutDates: events.filter { DailyWorkoutProgress.earnsWorkoutCredit(source: $0.source) }.map(\.date),
            exerciseMinutes: todayLog?.appleExerciseMinutes ?? 0,
            sessionMinutes: DailyWorkoutProgress.sessionMinutes(intervals: intervals, asOf: now, calendar: calendar),
            goalMinutes: targetMinutes, weeklyGoal: weeklyGoal, asOf: now, calendar: calendar
        )
    }

    var body: some View {
        let snapshot = progress
        let coach = DailyWorkoutCoach.make(progress: snapshot, resting: recommendedRest,
                                           easing: recovery == .downgrade, calendar: calendar)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionEyebrow(title: "YOUR DAILY WIN", tint: Theme.matcha)
                    Text(coach.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if profiles.first?.mascotEnabled == true && !dynamicTypeSize.isAccessibilitySize {
                    MascotView(state: snapshot.trainedToday ? .proud : .neutral,
                               variant: profiles.first?.mascotVariant ?? "ninja_male")
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                }
            }
            Text(coach.message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.dailyCoach")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.l) {
                    rings(snapshot).frame(width: 128, height: 128)
                    ringLegend(snapshot)
                }
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    rings(snapshot).frame(width: 128, height: 128).frame(maxWidth: .infinity)
                    ringLegend(snapshot)
                }
            }

            if let errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
            if recommendedRest {
                Label("Rest day. Your workout rings can wait.", systemImage: "leaf.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.matcha)
                if recovery != .rest && (profiles.first?.sickDayActiveUntil ?? .distantPast) < now {
                    Button("Change today's plan") { saveRestDay(false) }
                        .accessibilityIdentifier("today.resumePlan")
                }
            } else if snapshot.trainedToday {
                Label("Daily win earned · +50 XP", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.matcha)
                    .accessibilityIdentifier("today.workoutWin")
                NavigationLink("Explore workouts") { TrainingHubView() }
            } else {
                sessionActions
            }

            weeklyPath(snapshot)
            levelProgress(snapshot)

            DisclosureGroup("How your progress works") {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("Move uses Apple Health exercise minutes or your saved session time, whichever is higher. Workout closes after a recorded session. Week counts distinct workout days, Monday to Sunday.")
                    Text("Earn 50 XP per workout day and a new level every 250 XP. Rest and missed days never remove XP. Health workouts receive credit when they sync; you don't need to log them again.")
                    Picker("Weekly workout days", selection: $weeklyGoal) {
                        ForEach(1...7, id: \.self) { Text("\($0) days").tag($0) }
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, Theme.Space.s)
            }
            .font(.caption)
            .accessibilityIdentifier("today.progressExplanation")
        }
        .padding(Theme.Space.l)
        // A List row's automatic button style can activate several controls
        // together. Each workout/rest action must handle only its own tap.
        .buttonStyle(.borderless)
        .dojoCardSurface()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: snapshot.movementProgress)
        .sensoryFeedback(.success, trigger: snapshot.trainedToday) { old, new in !old && new }
        .task {
            do { try CustomActivityService(modelContext: modelContext).seedDefaultsIfNeeded() }
            catch { errorMessage = "Couldn't load activities. \(error.localizedDescription)" }
        }
        .task(id: now) {
            if let profile = profiles.first {
                let detail = RecoveryGate(modelContext: modelContext, timezone: calendar.timeZone)
                    .evaluateDetailed(profile: profile, asOf: now)
                recovery = detail.hasData ? detail.recommendation : .normal
            }
        }
    }

    private var sessionActions: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("How much time feels doable?").font(.subheadline.weight(.semibold))
            Picker("Daily movement goal", selection: $goalMinutes) {
                ForEach([5, 10, 20], id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("today.workoutDuration")
            if let template = selectedTemplate {
                Menu {
                    ForEach(templates) { option in
                        Button(option.name, systemImage: option.systemImageName) { activityName = option.name }
                    }
                } label: {
                    Label("Activity: \(template.name)", systemImage: "chevron.up.chevron.down")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
                NavigationLink {
                    CustomActivitySessionView(template: template, suggestedDurationMinutes: targetMinutes, startsImmediately: true)
                } label: {
                    Label("Start \(targetMinutes)-min \(template.name.lowercased())", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.matcha)
                .accessibilityIdentifier("today.startWorkout")
            } else {
                NavigationLink("Choose a workout") { TrainingHubView() }
            }
            Button("I need a rest day") { saveRestDay(true) }
                .font(.subheadline)
                .frame(minHeight: 44)
                .accessibilityIdentifier("today.restDay")
        }
    }

    private func rings(_ snapshot: DailyWorkoutProgress) -> some View {
        ZStack {
            ring(progress: snapshot.movementProgress, tint: Theme.kurenai, inset: 0)
            ring(progress: snapshot.trainedToday ? 1 : 0, tint: Theme.matcha, inset: 14)
            ring(progress: snapshot.weeklyProgress, tint: Theme.ai, inset: 28)
            VStack(spacing: 0) {
                Image(systemName: recommendedRest ? "leaf.fill" : "bolt.fill")
                    .foregroundStyle(recommendedRest ? Theme.matcha : Theme.kin)
                Text(recommendedRest ? "REST" : "TODAY").font(.system(size: 8, weight: .bold))
            }
        }
        .accessibilityHidden(true)
    }

    private func ring(progress: Double, tint: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(tint.opacity(0.16), lineWidth: 10)
            Circle().trim(from: 0, to: progress)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset + 5)
    }

    private func ringLegend(_ snapshot: DailyWorkoutProgress) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            legend("Move", value: "\(snapshot.movementMinutes)/\(snapshot.goalMinutes) min", tint: Theme.kurenai)
            legend("Workout", value: snapshot.trainedToday ? "Done today" : "One session", tint: Theme.matcha)
            legend("Week", value: "\(snapshot.daysThisWeek)/\(snapshot.weeklyGoal) days", tint: Theme.ai)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func legend(_ name: String, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(name).font(.subheadline.weight(.semibold))
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func weeklyPath(_ snapshot: DailyWorkoutProgress) -> some View {
        HStack(spacing: 0) {
            ForEach(snapshot.weekDays, id: \.self) { day in
                let done = snapshot.workoutDays.contains(day)
                let current = day == snapshot.today
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(done ? Theme.matcha : (current ? Theme.kin : Theme.textTertiary))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))), \(done ? "workout complete" : current ? "today" : "no workout recorded")")
            }
        }
    }

    private func levelProgress(_ snapshot: DailyWorkoutProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Level \(snapshot.level)", systemImage: "sparkles").foregroundStyle(Theme.kin)
                Spacer()
                Text("\(snapshot.totalXP) XP").monospacedDigit()
            }
            .font(.caption.weight(.bold))
            ProgressView(value: Double(snapshot.xpInLevel), total: Double(DailyWorkoutProgress.xpPerLevel))
                .tint(Theme.kin)
                .accessibilityLabel("Level \(snapshot.level), \(snapshot.xpToNextLevel) XP to next level")
            Text("\(snapshot.xpToNextLevel) XP to your next level · your progress stays yours")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }

    private func interval(start: Date, minutes: Int) -> DateInterval {
        DateInterval(start: start, duration: TimeInterval(max(0, minutes)) * 60)
    }

    private func saveRestDay(_ resting: Bool) {
        let log = DailyLogStore.forUser(modelContext: modelContext).upsert(for: now)
        let previous = log.metadataBlob
        log.setMetadata("dailyWorkout.restDay", value: resting)
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            log.metadataBlob = previous
            errorMessage = "Couldn't save your plan. Please try again."
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView { DailyWorkoutCard(now: Date()).padding() }
            .background(DojoBackground())
    }
    .modelContainer(dailyWorkoutPreviewContainer)
}

@MainActor
private let dailyWorkoutPreviewContainer: ModelContainer = {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let profile = UserProfile(name: "Alex")
    profile.onboardingCompleted = true
    container.mainContext.insert(profile)
    let log = DailyLogStore.forUser(modelContext: container.mainContext).upsert(for: Date())
    log.appleExerciseMinutes = 6
    return container
}()
