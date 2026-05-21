import SwiftUI
import SwiftData
import CloudKit
import CoreTransferable
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var travelDays: Int = 7
    @State private var graceFeedback: String?
    @State private var showingKeyEntry = false
    @State private var apiKeyStatus: APIKeyStatus = .unknown
    // M4.2 — Data section state
    @State private var lastSyncDate: Date?
    @State private var hkSyncBusy: Bool = false
    @State private var hkSyncFeedback: String?
    @State private var iCloudAccountStatus: CKAccountStatus = .couldNotDetermine
    @State private var exportData: Data?
    @State private var exportFeedback: String?

    enum APIKeyStatus {
        case unknown, set, missing
    }

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    profileForm(profile: profile)
                } else {
                    ProgressView()
                        .task {
                            _ = ProfileService.currentOrCreate(modelContext: modelContext)
                        }
                }
            }
            .navigationTitle("Settings")
            .onAppear { refreshAPIKeyStatus() }
            .sheet(isPresented: $showingKeyEntry) {
                APIKeyEntrySheet { _ in
                    refreshAPIKeyStatus()
                }
            }
        }
    }

    private var apiKeyStatusText: String {
        switch apiKeyStatus {
        case .unknown: return "Checking…"
        case .set: return "Set"
        case .missing: return "Not set"
        }
    }

    private func refreshAPIKeyStatus() {
        do {
            let key = try KeychainService.shared.getApiKey()
            apiKeyStatus = key.isEmpty ? .missing : .set
        } catch {
            apiKeyStatus = .missing
        }
    }

    /// Pre-populated mailto: URL for the 30-day TestFlight feedback loop.
    /// Subject + body templated so both Clay and his wife send structured
    /// notes. No infrastructure, no SDKs, no analytics — just email.
    // MARK: - M4.2 Data section

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Button {
                Task { await refreshFromHealthKit() }
            } label: {
                HStack {
                    Label("Refresh from HealthKit", systemImage: "heart.text.square")
                    Spacer()
                    if hkSyncBusy { ProgressView() }
                }
            }
            .disabled(hkSyncBusy)

            if exportData == nil {
                Button {
                    prepareExport()
                } label: {
                    Label("Prepare export", systemImage: "square.and.arrow.up")
                }
            } else if let data = exportData {
                ShareLink(item: ExportFile(data: data),
                          preview: SharePreview("PersonalOptimization-export.json")) {
                    Label("Share export (\(formattedSize(data.count)))", systemImage: "square.and.arrow.up.fill")
                }
            }

            HStack {
                Label("iCloud account", systemImage: iCloudIcon)
                Spacer()
                Text(iCloudStatusText)
                    .foregroundStyle(iCloudStatusColor)
                    .font(.caption)
            }

            if let lastSyncDate {
                HStack {
                    Label("Last HealthKit sync", systemImage: "clock")
                    Spacer()
                    Text(relativeText(lastSyncDate))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if let hkSyncFeedback {
                Text(hkSyncFeedback)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let exportFeedback {
                Text(exportFeedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Your data lives in iCloud private database. Reinstalling the app restores your schedule, logs, streaks, and AI history when you sign back in with the same Apple ID. The Anthropic API key syncs via iCloud Keychain.")
        }
        .task {
            await loadDataSectionState()
        }
    }

    private var iCloudIcon: String {
        switch iCloudAccountStatus {
        case .available: return "icloud.fill"
        case .noAccount: return "icloud.slash"
        default: return "icloud"
        }
    }

    private var iCloudStatusText: String {
        switch iCloudAccountStatus {
        case .available:                return "Signed in"
        case .noAccount:                return "Not signed in"
        case .restricted:               return "Restricted"
        case .temporarilyUnavailable:   return "Unavailable"
        case .couldNotDetermine:        return "Checking…"
        @unknown default:               return "Unknown"
        }
    }

    private var iCloudStatusColor: Color {
        switch iCloudAccountStatus {
        case .available: return .green
        case .noAccount, .restricted: return .orange
        default: return .secondary
        }
    }

    private func loadDataSectionState() async {
        // Most recent DailyLog timestamp tells us when HK last wrote.
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let mostRecentSync = logs.compactMap(\.healthKitSyncedAt).max()
        lastSyncDate = mostRecentSync

        // iCloud account status — cheap call to CKContainer.
        let container = CKContainer(identifier: "iCloud.com.rawlins.PersonalOptimization")
        if let status = try? await container.accountStatus() {
            iCloudAccountStatus = status
        }
    }

    private func refreshFromHealthKit() async {
        hkSyncBusy = true
        hkSyncFeedback = nil
        defer { hkSyncBusy = false }

        // Request auth (no-op if already granted) then sync today.
        _ = try? await LiveHealthKitService.shared.requestAuthorization()
        let service = HealthKitSyncService(modelContext: modelContext)
        _ = await service.syncToday()

        lastSyncDate = Date()
        hkSyncFeedback = "Refreshed."
    }

    private func prepareExport() {
        do {
            let data = try JSONExportService.export(modelContext: modelContext)
            exportData = data
            exportFeedback = "Ready to share — tap above."
        } catch {
            exportFeedback = "Export failed: \(error.localizedDescription)"
        }
    }

    private func relativeText(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        let day: TimeInterval = 86_400
        switch elapsed {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(elapsed / 60))m ago"
        case ..<day:  return "\(Int(elapsed / 3600))h ago"
        case ..<(7 * day): return "\(Int(elapsed / day))d ago"
        default:
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return f.string(from: date)
        }
    }

    private func formattedSize(_ byteCount: Int) -> String {
        ByteCountFormatter().string(fromByteCount: Int64(byteCount))
    }

    /// Friendly relative timestamp for "Last generated: ..." in the Schedule
     /// section. Drops to absolute date when older than a week.
    private func lastGeneratedText(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        let day: TimeInterval = 86_400
        switch elapsed {
        case ..<3600:               return "just now"
        case ..<day:                return "today"
        case ..<(2 * day):          return "yesterday"
        case ..<(7 * day):          return "\(Int(elapsed / day))d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func feedbackMailtoURL(profile: UserProfile?) -> URL? {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let variant = profile?.mascotVariant ?? "ninja_male"
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let today = dateFmt.string(from: Date())

        let subject = "PersonalOptimization feedback \(today)"
        let body = """
            App version: \(appVersion) (\(appBuild))
            Mascot variant: \(variant)
            Date: \(today)

            What's working:


            What's broken:


            What's missing:

            """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "clayvis27@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    @ViewBuilder
    private func profileForm(profile: UserProfile) -> some View {
        @Bindable var profile = profile
        Form {
            dataSection
            Section("Profile") {
                LabeledContent("Name") {
                    TextField("Name", text: $profile.name)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Date of birth", selection: $profile.dob, displayedComponents: .date)
                Picker("Sex", selection: $profile.sex) {
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                }
                LabeledContent("Height (in)") {
                    TextField("74", value: $profile.heightInches, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Weight (lb)") {
                    TextField("205", value: $profile.weightLbs, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Time zone") {
                LabeledContent("IANA identifier", value: profile.timezone)
                Toggle("Travel mode: follow device", isOn: $profile.travelModeFollowsDevice)
                Text("When on, day boundaries follow the device's time zone instead of your pinned profile time zone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Quiet hours") {
                LabeledContent("Sleep starts") {
                    TextField("22:00", text: $profile.sleepWindowStartHHMM)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                }
                LabeledContent("Sleep ends") {
                    TextField("07:00", text: $profile.sleepWindowEndHHMM)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                }
                Text("Hydration and other check-in notifications are suppressed during this window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Fasting window") {
                Stepper("Start hour: \(profile.fastWindowStartHour)", value: $profile.fastWindowStartHour, in: 0...23)
                Stepper("End hour: \(profile.fastWindowEndHour)", value: $profile.fastWindowEndHour, in: 0...23)
            }

            Section("Hydration") {
                LabeledContent("Bottle size (oz)") {
                    TextField("32", value: $profile.bottleSizeOz, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Quick-pick presets (oz)") {
                    TextField("4,8,12,16,20,24,32", text: $profile.hydrationQuickPicksOzCSV)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                }
            }

            Section {
                NavigationLink {
                    ScheduleGenerationView()
                } label: {
                    HStack {
                        Label("Generate with AI", systemImage: "sparkles")
                        if let last = profile.lastGeneratedAt {
                            Spacer()
                            Text(lastGeneratedText(last))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink {
                    ScheduleEditorView()
                } label: {
                    Label("Edit schedule", systemImage: "calendar")
                }
                NavigationLink {
                    ScheduleTemplateChooserView()
                } label: {
                    Label("Start fresh from template", systemImage: "doc.badge.gearshape")
                }
                NavigationLink {
                    ImplementationIntentionsView()
                } label: {
                    Label("Implementation intentions", systemImage: "arrow.right.circle.fill")
                }
            } header: {
                Text("Schedule")
            } footer: {
                if profile.lastGeneratedAt == nil {
                    Text("Build your week from goals + constraints, or pick a template.")
                }
            }

            Section("Goals & equipment") {
                LabeledContent("Primary goal") {
                    TextField("e.g., build muscle, stay sharp", text: Binding(
                        get: { profile.primaryGoal ?? "" },
                        set: { profile.primaryGoal = $0.isEmpty ? nil : $0 }
                    ))
                    .multilineTextAlignment(.trailing)
                }
                LabeledContent("Secondary goals") {
                    TextField("comma-separated", text: $profile.secondaryGoalsCSV)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                }
                Picker("Equipment access", selection: $profile.equipmentAccess) {
                    Text("Full gym").tag("gym")
                    Text("Home (full)").tag("home_full")
                    Text("Home (minimal)").tag("home_minimal")
                    Text("Bodyweight").tag("bodyweight")
                    Text("Outdoor").tag("outdoor")
                }
                Stepper("Weekly target: \(profile.weeklyTrainingTargetSessions) sessions", value: $profile.weeklyTrainingTargetSessions, in: 0...14)
                LabeledContent("Restrictions") {
                    TextField("injuries, dietary, time", text: $profile.restrictionsCSV)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                }
            }

            Section("AI") {
                Picker("Anthropic model", selection: $profile.anthropicModel) {
                    Text("Sonnet 4.6").tag("claude-sonnet-4-6")
                    Text("Opus 4.7").tag("claude-opus-4-7")
                    Text("Haiku 4.5").tag("claude-haiku-4-5-20251001")
                }
                Stepper(value: $profile.dailyTokenBudget, in: 0...500_000, step: 5_000) {
                    Text("Daily token budget: \(profile.dailyTokenBudget == 0 ? "Off" : "\(profile.dailyTokenBudget)")")
                }
                Text("0 disables Claude calls. Coach falls back to curated content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Sync API key across my Apple devices", isOn: $profile.apiKeyICloudSync)
                    .onChange(of: profile.apiKeyICloudSync) { _, newValue in
                        // Re-write the key with the requested posture so the
                        // stored item matches the user's preference immediately.
                        if let existing = try? KeychainService.shared.getApiKey(), !existing.isEmpty {
                            try? KeychainService.shared.setApiKey(existing, iCloudSync: newValue)
                        }
                    }
                Text(profile.apiKeyICloudSync
                    ? "Convenient: survives reinstall and reaches every Apple device on your iCloud account."
                    : "Stored on this device only. Stronger security posture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("API key")
                    Spacer()
                    Text(apiKeyStatusText)
                        .font(.caption)
                        .foregroundStyle(apiKeyStatus == .set ? .green : .secondary)
                }
                Button {
                    showingKeyEntry = true
                } label: {
                    Label(apiKeyStatus == .set ? "Update API key" : "Set API key", systemImage: "key.fill")
                }
                if apiKeyStatus == .set {
                    Button(role: .destructive) {
                        try? KeychainService.shared.deleteApiKey()
                        refreshAPIKeyStatus()
                    } label: {
                        Label("Remove API key", systemImage: "trash")
                    }
                }
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
            }

            Section {
                NavigationLink {
                    AchievementsView()
                } label: {
                    Label("Achievements", systemImage: "trophy.fill")
                }
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                if let url = feedbackMailtoURL(profile: profile) {
                    Link(destination: url) {
                        Label("Send feedback", systemImage: "envelope")
                    }
                }
            }

            Section("Mascot") {
                Toggle("Show mascot", isOn: $profile.mascotEnabled)
                Toggle("Reduced motion", isOn: $profile.reducedMotion)
                NavigationLink {
                    MascotVariantPickerView()
                } label: {
                    HStack {
                        Label("Variant", systemImage: "person.2.fill")
                        Spacer()
                        Text(MascotVariant(rawValue: profile.mascotVariant)?.displayName ?? "Ninja (male)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Coaching") {
                NavigationLink {
                    PersonaQuestionnaireView()
                } label: {
                    Label("Coach learns about you", systemImage: "person.text.rectangle")
                }
                Picker("Motivation style", selection: $profile.motivationStyle) {
                    Text("Balanced").tag("balanced")
                    Text("Stoic").tag("stoic")
                    Text("Holistic").tag("holistic")
                    Text("Warrior").tag("warrior")
                    Text("Spiritual").tag("spiritual")
                    Text("Scientific").tag("scientific")
                    Text("Custom").tag("custom")
                }
                if profile.motivationStyle == "custom" {
                    TextField("Custom style notes",
                              text: Binding(
                                get: { profile.customStylePrompt ?? "" },
                                set: { profile.customStylePrompt = $0.isEmpty ? nil : $0 }
                              ),
                              axis: .vertical)
                    .lineLimit(2...5)
                }
                Toggle("AI-generated quotes", isOn: $profile.aiQuotesEnabled)
            }

            Section("Training") {
                Toggle("Achilles check-in after basketball", isOn: $profile.achillesCheckInEnabled)
                NavigationLink {
                    CustomActivitiesSettingsView()
                } label: {
                    Label("Activities (running, HIIT, yoga…)", systemImage: "figure.run")
                }
            }

            Section("Partnership") {
                NavigationLink {
                    PartnerSettingsView()
                } label: {
                    Label("Partner mode", systemImage: "person.2.fill")
                }
            }

            graceModeSection(profile: profile)

            Section("Rollout") {
                Picker("Phase", selection: $profile.rolloutPhase) {
                    Text("Weeks 1-2 (training-day fast)").tag(1)
                    Text("Weeks 3+ (16:8 daily)").tag(2)
                }
            }
        }
    }

    @ViewBuilder
    private func graceModeSection(profile: UserProfile) -> some View {
        @Bindable var profile = profile
        let now = Date()
        let sickActive = (profile.sickDayActiveUntil ?? .distantPast) >= now
        let travelActive = (profile.travelModeActiveUntil ?? .distantPast) >= now

        Section {
            Toggle("Sick today", isOn: Binding(
                get: { sickActive },
                set: { newValue in
                    let service = StreakService(modelContext: modelContext)
                    if newValue {
                        try? service.activateSickDay()
                        graceFeedback = IdentityCopy.sickBanner
                    } else {
                        profile.sickDayActiveUntil = nil
                    }
                }
            ))
            .sensoryFeedback(.selection, trigger: sickActive)

            HStack {
                Text("Travel mode")
                Spacer()
                if travelActive {
                    Button("End travel mode", role: .destructive) {
                        try? StreakService(modelContext: modelContext).deactivateTravelMode()
                    }
                } else {
                    Stepper("\(travelDays) days", value: $travelDays, in: 1...14)
                        .fixedSize()
                }
            }

            if !travelActive {
                Button {
                    try? StreakService(modelContext: modelContext).activateTravelMode(days: travelDays)
                    graceFeedback = IdentityCopy.travelBanner
                } label: {
                    Label("Activate travel mode", systemImage: "airplane.departure")
                }
                .sensoryFeedback(.success, trigger: travelActive)
            }

            if let feedback = graceFeedback {
                Text(feedback).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Streak grace")
        } footer: {
            Text("Sick day covers today. Travel mode covers the next \(travelDays) days. Streaks are preserved through ledger entries; nothing fakes a workout.")
        }
    }
}

/// Transferable wrapper for ShareLink. ExportFile wraps the JSON Data with
/// the correct UTI + filename so the iOS share sheet treats it as a
/// downloadable .json file rather than raw text.
struct ExportFile: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            file.data
        }
        .suggestedFileName("PersonalOptimization-export.json")
    }
}

#Preview("Settings") {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return SettingsView().modelContainer(container)
}
