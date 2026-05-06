import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var travelDays: Int = 7
    @State private var graceFeedback: String?
    @State private var showingKeyEntry = false
    @State private var apiKeyStatus: APIKeyStatus = .unknown

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

    @ViewBuilder
    private func profileForm(profile: UserProfile) -> some View {
        @Bindable var profile = profile
        Form {
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

            Section("Schedule") {
                NavigationLink {
                    ScheduleEditorView()
                } label: {
                    Label("Edit schedule", systemImage: "calendar")
                }
            }

            Section("AI") {
                Picker("Anthropic model", selection: $profile.anthropicModel) {
                    Text("Sonnet 4.6").tag("claude-sonnet-4-6")
                    Text("Opus 4.7").tag("claude-opus-4-7")
                    Text("Haiku 4.5").tag("claude-haiku-4-5-20251001")
                }
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

            Section("Mascot") {
                Toggle("Show mascot", isOn: $profile.mascotEnabled)
                Toggle("Reduced motion", isOn: $profile.reducedMotion)
            }

            Section("Coaching") {
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

#Preview("Settings") {
    let schema = Schema(versionedSchema: SchemaV4.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return SettingsView().modelContainer(container)
}
