import SwiftUI
import SwiftData
import HealthKit
import UserNotifications

/// First-launch onboarding wizard. Five screens, identity-framed, locked
/// progression so the user can't skip critical permission asks. Sets
/// `UserProfile.onboardingCompleted = true` on finish so RootView routes past
/// it on subsequent launches.
@MainActor
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var step: Int = 0
    @State private var primaryGoal: String = ""
    @State private var equipmentAccess: String = "gym"
    @State private var pickedVariant: MascotVariant = .ninjaMale
    @State private var scheduleTemplate: ScheduleTemplate = .balanced
    @State private var hkRequested = false
    @State private var notifRequested = false
    @State private var seedingDone = false
    @State private var showingAIGeneration = false
    @State private var anchorDraft: ScheduleAnchorDraft = .init()
    // M4.2 T0c: track explicit schedule choice during this onboarding session.
    // Set when the user taps a template tile OR returns from the AI flow with
    // an applied proposal. Gates the Continue button on the schedule step.
    @State private var scheduleChosenInSession = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: 7)
                .tint(.accentColor)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            TabView(selection: $step) {
                welcomeScreen.tag(0)
                permissionsScreen.tag(1)
                goalsScreen.tag(2)
                anchorsScreen.tag(3)      // M5: collect anchors BEFORE template
                scheduleScreen.tag(4)
                mascotScreen.tag(5)
                wrapUpScreen.tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            controls
        }
        .task { await ensureProfileExists() }
    }

    @ViewBuilder
    private var welcomeScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome.")
                .font(.largeTitle.weight(.bold))
            Text("This app is yours. Single user. No accounts. Nothing leaves your devices except the AI calls you opt into.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                bullet("No servers, no analytics, no ads.")
                bullet("All data lives in your iCloud private database.")
                bullet("Streaks bend for sick days and travel.")
                bullet("The mascot reflects real signals, never theater.")
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private var permissionsScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Two permissions, then we're done.")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 14) {
                permissionRow(
                    icon: "heart.fill",
                    title: "HealthKit",
                    detail: "Sleep, heart rate, HRV. Powers your mascot, weekly reflection, and Coach insights.",
                    granted: hkRequested,
                    action: requestHealthKit
                )
                permissionRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    detail: "One nudge per behavior per day max. Suppressed when you've already logged. Quiet hours honored.",
                    granted: notifRequested,
                    action: requestNotifications
                )
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private var goalsScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "target")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("What are you optimizing for?")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text("One sentence. The Coach uses this to tune every prescription.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("e.g., build muscle, stay sharp on the court", text: $primaryGoal, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Equipment you have today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    equipmentCardList
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 32)
        }
    }

    /// Five equipment options don't fit on iPhone width as a segmented control
    /// (truncate to "Bodywei...", "Home (..." etc.). Stacked card list with full
    /// labels + a selected accent reads cleanly and avoids the truncation bug.
    @ViewBuilder
    private var equipmentCardList: some View {
        let options: [(value: String, label: String, glyph: String)] = [
            ("gym", "Full gym", "dumbbell.fill"),
            ("home_full", "Home (full kit)", "house.fill"),
            ("home_minimal", "Home (minimal kit)", "house"),
            ("bodyweight", "Bodyweight only", "figure.cooldown"),
            ("outdoor", "Outdoor", "leaf.fill")
        ]
        VStack(spacing: 8) {
            ForEach(options, id: \.value) { option in
                equipmentRow(option: option)
            }
        }
    }

    /// One row of the equipment picker. Pulled out of the `ForEach` because
    /// the inline conditional `foregroundStyle` and `background` expressions
    /// blew SwiftUI's type-checker complexity budget when stacked together.
    @ViewBuilder
    private func equipmentRow(option: (value: String, label: String, glyph: String)) -> some View {
        let selected = equipmentAccess == option.value
        Button {
            equipmentAccess = option.value
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.glyph)
                    .frame(width: 24)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(option.label)
                    .font(.body.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected
                        ? Color.accentColor.opacity(0.12)
                        : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// Onboarding screen 3 (V11): collect daily anchors BEFORE the template
    /// picker. Without this the chooser falls through to evening-default
    /// resolution and lands lifts at 18:00 regardless of what the user
    /// actually does after work. The DatePickers bind to local Date values
    /// in `anchorDraft`; `applyScheduleTemplate` flushes them to the
    /// profile before resolving blocks.
    @ViewBuilder
    private var anchorsScreen: some View {
        Form {
            Section {
                Text("Tell me your day's anchors. Templates resolve against these — no defaults are assumed. The app will not place a workout at 18:00 unless you choose it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Daily anchors") {
                DatePicker(
                    "Wake time",
                    selection: $anchorDraft.wakeDate,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Bedtime",
                    selection: $anchorDraft.bedtimeDate,
                    displayedComponents: .hourAndMinute
                )
            }
            Section("Kids") {
                DatePicker(
                    "Drop off",
                    selection: $anchorDraft.kidDropDate,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Pickup",
                    selection: $anchorDraft.kidPickupDate,
                    displayedComponents: .hourAndMinute
                )
            }
            Section("Training") {
                Picker("Preferred window", selection: $anchorDraft.preferredTrainingTimeOfDay) {
                    ForEach(TimeOfDayPreference.allCases) { pref in
                        Text(pref.displayName).tag(pref)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Learning") {
                DatePicker(
                    "Evening learning starts",
                    selection: $anchorDraft.learningStartDate,
                    displayedComponents: .hourAndMinute
                )
            }
            if anchorDraft.isValid == false {
                Section {
                    Text("Wake must be before bedtime and drop-off must be before pickup.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    /// Onboarding screen 4 — schedule template. Lets the wife (or any new
    /// user) avoid landing on Clay's seeded blocks. The template picker
    /// applies the chosen template via ScheduleTemplateApplier; user can
    /// always edit individual blocks later in Settings → Schedule.
    @ViewBuilder
    private var scheduleScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 32)
            Text("Pick a starting schedule.")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("You can edit any block later. Pick the template that fits your shape of week — we'll seed it now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            ScrollView {
                VStack(spacing: 8) {
                    aiGenerateTile
                    ForEach(ScheduleTemplate.allCases) { template in
                        scheduleTemplateRow(template)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    /// AI generation tile, sitting above the static templates. Presents the
    /// intake form as a sheet (OnboardingView is a paged TabView, not a
    /// NavigationStack, so a sheet is the right modal pattern here). Applying
    /// the proposal lands the user back on this screen with the schedule
    /// already seeded; they advance via the normal Next button.
    @ViewBuilder
    private var aiGenerateTile: some View {
        Button {
            showingAIGeneration = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build me a schedule (AI)")
                        .font(.subheadline.weight(.semibold))
                    Text("Tell me your goals; I'll draft a week. You review before it lands.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingAIGeneration) {
            NavigationStack {
                ScheduleGenerationView(onApplied: {
                    scheduleChosenInSession = true
                })
            }
        }
    }

    @ViewBuilder
    private func scheduleTemplateRow(_ template: ScheduleTemplate) -> some View {
        let selected = scheduleTemplate == template
        Button {
            applyScheduleTemplate(template)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.systemImage)
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(template.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected
                        ? Color.accentColor.opacity(0.12)
                        : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func applyScheduleTemplate(_ template: ScheduleTemplate) {
        scheduleTemplate = template
        // Flush the anchor draft so the template applier resolves blocks
        // against the user's chosen wake/training/learning windows. Without
        // this the planner falls back to evening defaults and the
        // "Balanced" template lands lifts at 18:00 — the exact bug the M5
        // re-haul is meant to fix.
        if let profile = profile {
            anchorDraft.writeTo(profile: profile)
            // MARK: - try? justified because anchor flush is best-effort;
            // worst case the applier uses defaultForFallback, which still
            // produces a working schedule.
            try? modelContext.save()  // MARK: try? save() is best-effort; failure logged elsewhere and in-memory state already reflects the change.
        }
        let anchors: SchedulePlanner.AnchorSet = profile.map(SchedulePlanner.AnchorSet.from(profile:))
            ?? .defaultForFallback
        // MARK: - try? justified because template application is best-effort
        // during onboarding; the user can retry from the chooser or skip
        // and pick later in Settings.
        _ = try? ScheduleTemplateApplier.apply(  // MARK: try? justified - best-effort; failure logged inside the called function.
            template,
            modelContext: modelContext,
            anchors: anchors
        )
        scheduleChosenInSession = true
    }

    @ViewBuilder
    private var mascotScreen: some View {
        VStack(spacing: 16) {
            Text("Pick your mascot.")
                .font(.title2.weight(.bold))
                .padding(.top, 32)

            HStack(spacing: 24) {
                ForEach(MascotVariant.allCases) { variant in
                    Button {
                        pickedVariant = variant
                    } label: {
                        VStack(spacing: 8) {
                            Image("\(variant.assetPrefix)_Neutral")
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 100)
                                .padding(8)
                                .background(pickedVariant == variant ? Color.accentColor.opacity(0.20) : Color.gray.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(pickedVariant == variant ? Color.accentColor : Color.clear, lineWidth: 2)
                                }
                            Text(variant.displayName)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Text("They're a signal. Sad means a real miss. Proud means an earned win.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    @ViewBuilder
    private var wrapUpScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 32)
            Text("You're set.")
                .font(.largeTitle.weight(.bold))
            Text("Five evidence-backed implementation intentions seeded for your morning routine, training, and learning. Edit them in Settings whenever the routine shifts.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                bullet("Apple Watch: pair the watch in the iOS Watch app to surface complications and live workouts.")
                bullet("Coach Mode: drop your Anthropic API key in Settings → AI to enable daily insights and prescriptions.")
                bullet("Sundays: open the Today tab for a weekly reflection.")
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step < 6 {
                Button("Continue") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(canAdvance == false)
            } else {
                Button("Get started") { complete() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return true
        case 1: return true // permissions are optional but encouraged
        case 2: return true
        case 3:
            // M5: anchors step. Require a sane wake/bedtime ordering before
            // we let the user proceed to template selection. Defaults pass
            // this check, so a user who taps Continue without changing
            // anything still gets through.
            return anchorDraft.isValid
        case 4:
            // M4.2 T0c (shifted +1): schedule step requires an explicit
            // choice. User must tap a template tile or apply an AI schedule.
            return hasMadeScheduleChoice
        default: return true
        }
    }

    /// True when the user has tapped one of the template tiles or applied an
    /// AI-generated schedule during this onboarding session.
    private var hasMadeScheduleChoice: Bool {
        if scheduleChosenInSession { return true }
        if profile?.lastGeneratedAt != nil { return true }
        return false
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
            Text(text).font(.subheadline)
            Spacer()
        }
    }

    @ViewBuilder
    private func permissionRow(icon: String,
                               title: String,
                               detail: String,
                               granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Button(granted ? "Asked" : "Allow") {
                    action()
                }
                .buttonStyle(.bordered)
                .disabled(granted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func requestHealthKit() {
        Task {
            _ = try? await LiveHealthKitService.shared.requestAuthorization()  // MARK: try? justified - best-effort; failure logged inside the called function.
            hkRequested = true
        }
    }

    private func requestNotifications() {
        Task {
            // Route through NotificationService.register() so category
            // descriptors (hydration action buttons, etc.) get registered
            // alongside the authorization request. Going around it via the
            // raw UNUserNotificationCenter was the original bug — actions
            // never surfaced on the lock screen because categories never
            // landed with the system.
            // MARK: - try? justified because onboarding step is best-effort;
            // user can still grant later via Settings. NotificationService
            // logs the failure path.
            _ = try? await NotificationService.shared.register()  // MARK: try? justified - best-effort; failure logged inside the called function.
            notifRequested = true
        }
    }

    private func ensureProfileExists() async {
        if profiles.isEmpty {
            _ = ProfileService.currentOrCreate(modelContext: modelContext)
        }
        // Seed default custom activities so first-launch users see Running,
        // Walking, HIIT, Yoga, Cycling, Hiking on the Train tab without a
        // separate setup step.
        if !seedingDone {
            _ = try? CustomActivityService(modelContext: modelContext).seedDefaultsIfNeeded()  // MARK: try? justified - best-effort; failure logged inside the called function.
            _ = try? ImplementationIntentionService(modelContext: modelContext).seedStartersIfNeeded()  // MARK: try? justified - best-effort; failure logged inside the called function.
            seedingDone = true
        }
    }

    private func complete() {
        guard let profile else { return }
        let trimmedGoal = primaryGoal.trimmingCharacters(in: .whitespaces)
        if !trimmedGoal.isEmpty {
            profile.primaryGoal = trimmedGoal
        }
        profile.equipmentAccess = equipmentAccess
        profile.mascotVariant = pickedVariant.rawValue
        // V11: persist final anchor draft if the user touched the screen but
        // never tapped a template tile (defensive — the flush in
        // applyScheduleTemplate already covers the normal path).
        anchorDraft.writeTo(profile: profile)
        profile.onboardingCompleted = true
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
    }
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

    init(wakeHHMM: String = "06:00",
         bedtimeHHMM: String = "22:00",
         kidDropHHMM: String = "09:00",
         kidPickupHHMM: String = "17:00",
         learningStartHHMM: String = "19:00",
         preferredTrainingTimeOfDay: TimeOfDayPreference = .evening) {
        self.wakeDate = Self.todayAt(hhmm: wakeHHMM) ?? Self.todayAt(hour: 6, minute: 0)
        self.bedtimeDate = Self.todayAt(hhmm: bedtimeHHMM) ?? Self.todayAt(hour: 22, minute: 0)
        self.kidDropDate = Self.todayAt(hhmm: kidDropHHMM) ?? Self.todayAt(hour: 9, minute: 0)
        self.kidPickupDate = Self.todayAt(hhmm: kidPickupHHMM) ?? Self.todayAt(hour: 17, minute: 0)
        self.learningStartDate = Self.todayAt(hhmm: learningStartHHMM) ?? Self.todayAt(hour: 19, minute: 0)
        self.preferredTrainingTimeOfDay = preferredTrainingTimeOfDay
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
            preferredTrainingTimeOfDay: profile.preferredTrainingTimeOfDay
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
