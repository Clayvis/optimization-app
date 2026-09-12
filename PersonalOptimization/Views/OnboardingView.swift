import SwiftUI
import SwiftData

/// Two short steps. Only explicit profile choices are saved; permissions,
/// nutrition targets, and detailed schedules stay available in their surfaces.
@MainActor
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]
    @State private var draft = QuickProfileDraft()
    @State private var step = 0
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var prepared = false
    @FocusState private var editingField: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 2)
                    .tint(Theme.matcha)
                    .padding(.horizontal, 20)
                    .accessibilityLabel("Setup step \(step + 1) of 2")
                Form {
                    if step == 0 { profileFields }
                    else { goalFields }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                if let errorMessage {
                    ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                        .padding(.horizontal)
                }
                HStack {
                    if step > 0 {
                        Button("Back") { step = 0; errorMessage = nil }
                            .buttonStyle(.bordered)
                    }
                    Button { advance() } label: {
                        Text(step == 0 ? "Continue" : "Start my day")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.matcha)
                        .disabled(isSaving || !prepared)
                        .accessibilityIdentifier("onboarding.continue")
                }
                .padding(16)
            }
            .background(DojoBackground())
            .navigationTitle(step == 0 ? "Make it yours" : "Your daily plan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingField = nil }
                }
            }
            .task { prepare() }
        }
    }

    private var profileFields: some View {
        Group {
            Section {
                Text("Height and weight personalize workout estimates. You can edit your profile in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("About you") {
                TextField("Name (optional)", text: $draft.name)
                    .textContentType(.givenName)
                    .focused($editingField, equals: "name")
                    .accessibilityIdentifier("onboarding.name")
                Picker("Units", selection: Binding(
                    get: { draft.usesMetric },
                    set: { draft.changeUnits(toMetric: $0) }
                )) {
                    Text("ft / lb").tag(false)
                    Text("cm / kg").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("onboarding.units")
                if draft.usesMetric {
                    numberField("Height (cm)", placeholder: "e.g. 165", text: $draft.heightMajor, id: "height")
                } else {
                    numberField("Height (feet)", placeholder: "e.g. 5", text: $draft.heightMajor, id: "height")
                    numberField("Height (inches)", placeholder: "0", text: $draft.heightMinor, id: "inches")
                }
                numberField(draft.usesMetric ? "Weight (kg)" : "Weight (lb)",
                            placeholder: draft.usesMetric ? "e.g. 65" : "e.g. 145", text: $draft.weight, id: "weight")
            }
        }
    }

    private var goalFields: some View {
        Group {
            Section("What matters to you?") {
                Picker("Focus", selection: $draft.goal) {
                    Text("Build consistency").tag("Build a consistent routine")
                    Text("Get stronger").tag("Get stronger")
                    Text("Improve endurance").tag("Improve endurance")
                    Text("Move more").tag("Move more")
                    Text("Feel more energized").tag("Feel more energized")
                }
                .accessibilityIdentifier("onboarding.goal")
                Picker("Workout days per week", selection: $draft.weeklyWorkouts) {
                    ForEach(1...7, id: \.self) { Text("\($0) days").tag($0) }
                }
                .accessibilityIdentifier("onboarding.weeklyGoal")
                Picker("Time for a small session", selection: $draft.dailyMinutes) {
                    ForEach([5, 10, 20], id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("onboarding.minutes")
                Text("These become your workout targets on Today. Rest days keep your earned progress.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Where you train") {
                Picker("Equipment", selection: $draft.equipment) {
                    Text("Bodyweight").tag("bodyweight")
                    Text("Full gym").tag("gym")
                    Text("Home equipment").tag("home_full")
                    Text("A few basics").tag("home_minimal")
                    Text("Outdoors").tag("outdoor")
                }
            }
            Section("Your companion") {
                HStack {
                    ForEach(MascotVariant.allCases) { variant in
                        Button { draft.mascotVariant = variant.rawValue } label: {
                            VStack(spacing: 6) {
                                MascotView(state: .neutral, variant: variant.rawValue)
                                    .frame(width: 90, height: 90)
                                Text(variant.displayName).font(.caption)
                                Image(systemName: draft.mascotVariant == variant.rawValue
                                      ? "checkmark.circle.fill" : "circle")
                            }
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(draft.mascotVariant == variant.rawValue ? Theme.matcha : Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(variant.displayName)
                        .accessibilityIdentifier("onboarding.\(variant.rawValue)")
                        .accessibilityAddTraits(draft.mascotVariant == variant.rawValue ? .isSelected : [])
                    }
                }
                Text("A training partner for small wins, rest days, and fresh starts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func numberField(_ title: String, placeholder: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .keyboardType(.decimalPad)
                .frame(minHeight: 44)
                .focused($editingField, equals: id)
                .accessibilityLabel(title)
                .accessibilityIdentifier("onboarding.\(id)")
        }
        .contentShape(Rectangle())
        .onTapGesture { editingField = id }
        .accessibilityElement(children: .contain)
    }

    private func prepare() {
        guard !prepared else { return }
        _ = ProfileService.currentOrCreate(modelContext: modelContext)
        prepared = true
    }

    private func advance() {
        editingField = nil
        errorMessage = nil
        do {
            try draft.validateBody()
            if step == 0 {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = 1 }
                return
            }
            guard let profile = profiles.first else { return }
            isSaving = true
            defer { isSaving = false }
            try ProfileService.completeQuickSetup(draft, profile: profile, modelContext: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    OnboardingView().modelContainer(PersistenceBootstrap.inMemory())
}

/// Local-only draft model for the onboarding anchors screen. Holds the
/// DatePicker bindings as `Date` values (DatePicker requires Date, not
/// HH:MM strings) and converts to/from the profile's HH:MM string fields
/// on flush. Living inside OnboardingView so other surfaces (Settings
/// anchor editor) build their own draft from the live profile rather than
/// inheriting a half-filled in-memory shape.
struct ScheduleAnchorDraft {
    var wakeDate: Date
    var bedtimeDate: Date
    var kidDropDate: Date
    var kidPickupDate: Date
    var learningStartDate: Date
    var preferredTrainingTimeOfDay: TimeOfDayPreference
    /// Wall-clock training start, used when the preference is `.custom`.
    var trainingStartDate: Date

    init(wakeHHMM: String = "06:00",
         bedtimeHHMM: String = "22:00",
         kidDropHHMM: String = "09:00",
         kidPickupHHMM: String = "17:00",
         learningStartHHMM: String = "19:00",
         preferredTrainingTimeOfDay: TimeOfDayPreference = .evening,
         trainingWindowStartHHMM: String = "18:00") {
        self.wakeDate = Self.todayAt(hhmm: wakeHHMM) ?? Self.todayAt(hour: 6, minute: 0)
        self.bedtimeDate = Self.todayAt(hhmm: bedtimeHHMM) ?? Self.todayAt(hour: 22, minute: 0)
        self.kidDropDate = Self.todayAt(hhmm: kidDropHHMM) ?? Self.todayAt(hour: 9, minute: 0)
        self.kidPickupDate = Self.todayAt(hhmm: kidPickupHHMM) ?? Self.todayAt(hour: 17, minute: 0)
        self.learningStartDate = Self.todayAt(hhmm: learningStartHHMM) ?? Self.todayAt(hour: 19, minute: 0)
        self.preferredTrainingTimeOfDay = preferredTrainingTimeOfDay
        self.trainingStartDate = Self.todayAt(hhmm: trainingWindowStartHHMM) ?? Self.todayAt(hour: 18, minute: 0)
    }

    /// Validity gate for the Continue button: wake strictly before bedtime,
    /// drop-off strictly before pickup. Sub-minute equality counts as
    /// invalid (same anchor for both events is a configuration error).
    var isValid: Bool {
        wakeDate < bedtimeDate && kidDropDate < kidPickupDate
    }

    /// Flushes draft values into the profile's HH:MM string fields and
    /// preferred-training-window picker. Idempotent: writing twice with
    /// the same draft produces the same profile state.
    func writeTo(profile: UserProfile) {
        profile.wakeHHMM = Self.hhmm(wakeDate)
        profile.bedtimeHHMM = Self.hhmm(bedtimeDate)
        profile.kidDropoffHHMM = Self.hhmm(kidDropDate)
        profile.kidPickupHHMM = Self.hhmm(kidPickupDate)
        profile.learningWindowStartHHMM = Self.hhmm(learningStartDate)
        profile.preferredTrainingTimeOfDay = preferredTrainingTimeOfDay
        profile.trainingWindowStartHHMM = Self.hhmm(trainingStartDate)
    }

    /// Inverse of `writeTo`: builds a draft seeded from the profile's
    /// current anchor fields. Used by the Settings anchor editor.
    static func from(profile: UserProfile) -> ScheduleAnchorDraft {
        ScheduleAnchorDraft(
            wakeHHMM: profile.wakeHHMM,
            bedtimeHHMM: profile.bedtimeHHMM,
            kidDropHHMM: profile.kidDropoffHHMM,
            kidPickupHHMM: profile.kidPickupHHMM,
            learningStartHHMM: profile.learningWindowStartHHMM,
            preferredTrainingTimeOfDay: profile.preferredTrainingTimeOfDay,
            trainingWindowStartHHMM: profile.trainingWindowStartHHMM
        )
    }

    private static func todayAt(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func todayAt(hhmm: String) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              (0..<24).contains(h),
              (0..<60).contains(m) else { return nil }
        return todayAt(hour: h, minute: m)
    }

    private static func hhmm(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
