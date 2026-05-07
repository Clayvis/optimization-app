import SwiftUI
import SwiftData

/// Today's prescribed workout, surfaced on TodayView and TrainView. Identity-framed
/// copy ("Today's prescription for you" not "Generated workout"). One-tap accept,
/// modify, or skip. Tap card to expand full template + rationale.
@MainActor
struct PrescribedWorkoutCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor(\PrescribedWorkout.generatedAt, order: .reverse)])
    private var prescriptions: [PrescribedWorkout]

    @State private var loading = false
    @State private var errorMessage: String?
    @State private var apiKeyMissing = false
    @State private var showingDetail = false
    @State private var skipReason: String = ""
    @State private var showingSkipSheet = false

    private var profile: UserProfile? { profiles.first }

    private var todays: PrescribedWorkout? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let day = cal.startOfDay(for: Date())
        return prescriptions.first(where: { cal.isDate($0.forDate, inSameDayAs: day) })
    }

    var body: some View {
        Button {
            if apiKeyMissing { return }
            if todays != nil { showingDetail = true }
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .task { await ensureLoaded() }
        .onAppear {
            // Re-check API key whenever the card surfaces so a Settings-side
            // change is reflected immediately. Without this, removing or
            // setting the key would only take effect after a full relaunch.
            apiKeyMissing = !keychainHasApiKey()
        }
        .sheet(isPresented: $showingDetail) {
            if let p = todays {
                PrescribedWorkoutDetailSheet(prescription: p)
            }
        }
        .sheet(isPresented: $showingSkipSheet) {
            skipSheet
        }
    }

    private func keychainHasApiKey() -> Bool {
        do {
            let key = try KeychainService.shared.getApiKey()
            return !key.isEmpty
        } catch {
            return false
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "figure.run.circle.fill")
                    .foregroundStyle(.tint)
                Text("TODAY'S PRESCRIPTION FOR YOU")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                }
            }

            if apiKeyMissing {
                Text("Set your Anthropic API key in Settings to enable Coach prescriptions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let p = todays {
                Text(p.workoutType.displayName)
                    .font(.title2.weight(.semibold))
                if !p.rationale.isEmpty {
                    Text(p.rationale)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actionRow(prescription: p)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                Text("Tap to receive today's prescribed workout.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await generate(force: true) }
                } label: {
                    Label("Generate", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func actionRow(prescription: PrescribedWorkout) -> some View {
        HStack(spacing: 8) {
            if prescription.status == .suggested || prescription.status == .modified {
                actionButton(label: "Accept",
                             systemImage: "checkmark",
                             role: nil,
                             prominent: true) {
                    accept(prescription: prescription)
                }
                actionButton(label: "Modify",
                             systemImage: "pencil",
                             role: nil,
                             prominent: false) {
                    showingDetail = true
                }
                actionButton(label: "Skip",
                             systemImage: "xmark",
                             role: .destructive,
                             prominent: false) {
                    skipReason = ""
                    showingSkipSheet = true
                }
            } else {
                Text(statusBadge(for: prescription.status))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeColor(for: prescription.status).opacity(0.18))
                    .clipShape(Capsule())
                Spacer()
                Button {
                    Task { await generate(force: true) }
                } label: {
                    Label("Re-prescribe", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// Compact, equal-width action button. Icon stacked over a one-word label so
    /// nothing wraps awkwardly across narrow rows. Each button gets the same
    /// width via `frame(maxWidth: .infinity)`.
    @ViewBuilder
    private func actionButton(label: String,
                              systemImage: String,
                              role: ButtonRole?,
                              prominent: Bool,
                              action: @escaping () -> Void) -> some View {
        let button = Button(role: role, action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .accessibilityLabel(label)

        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var skipSheet: some View {
        NavigationStack {
            Form {
                Section("Why skip today?") {
                    TextField("Reason (optional)", text: $skipReason)
                }
                Section {
                    Text("Skipping logs your honest reason. We'll never fake a session to keep a streak.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Skip workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSkipSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip") {
                        if let p = todays { skip(prescription: p) }
                        showingSkipSheet = false
                    }
                }
            }
        }
    }

    private func accept(prescription: PrescribedWorkout) {
        prescription.status = .accepted
        try? modelContext.save()
    }

    private func skip(prescription: PrescribedWorkout) {
        prescription.status = .skipped
        let reason = skipReason.trimmingCharacters(in: .whitespaces)
        if !reason.isEmpty {
            prescription.rationale = "[skipped: \(reason)] " + prescription.rationale
        }
        try? modelContext.save()
    }

    private func generate(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let service = CoachService(modelContext: modelContext)
        do {
            _ = try await service.prescribeTodaysWorkout(forceRefresh: force)
            errorMessage = nil
            apiKeyMissing = false
        } catch CoachServiceError.missingAPIKey {
            apiKeyMissing = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func ensureLoaded() async {
        // Auto-generate at most once per day if no prescription exists yet.
        if todays == nil, !loading, !apiKeyMissing {
            await generate(force: false)
        }
    }

    private func statusBadge(for status: PrescribedWorkoutStatus) -> String {
        switch status {
        case .accepted: return "ACCEPTED"
        case .modified: return "MODIFIED"
        case .skipped: return "SKIPPED"
        case .completed: return "COMPLETED"
        case .suggested: return "SUGGESTED"
        }
    }

    private func badgeColor(for status: PrescribedWorkoutStatus) -> Color {
        switch status {
        case .accepted, .completed: return .green
        case .modified: return .blue
        case .skipped: return .orange
        case .suggested: return .gray
        }
    }

    private var accessibilityLabel: String {
        if apiKeyMissing { return "Coach prescription disabled. Set API key." }
        if let p = todays { return "Today's prescription: \(p.workoutType.displayName). \(p.rationale)" }
        return "Today's prescription pending"
    }
}

private struct PrescribedWorkoutDetailSheet: View {
    @Bindable var prescription: PrescribedWorkout
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Text(prescription.workoutType.displayName)
                        .font(.title3.weight(.semibold))
                }
                Section("Rationale") {
                    Text(prescription.rationale)
                        .font(.body)
                }
                Section("Template (raw)") {
                    Text(prescription.template)
                        .font(.caption.monospaced())
                }
                Section("Status") {
                    Picker("Status", selection: Binding(
                        get: { prescription.status },
                        set: { prescription.status = $0 }
                    )) {
                        ForEach(PrescribedWorkoutStatus.allCases, id: \.rawValue) { s in
                            Text(s.rawValue.capitalized).tag(s)
                        }
                    }
                }
                Section("Token usage") {
                    LabeledContent("Tokens", value: "\(prescription.tokenUsage)")
                    LabeledContent("Model", value: prescription.modelUsed)
                }
            }
            .navigationTitle("Prescription")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
