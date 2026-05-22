import SwiftUI
import SwiftData

struct FastingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var service: FastingService?
    @State private var showingBreakSheet = false
    @State private var showingManualEndSheet = false
    @State private var loadError: String?
    @State private var actionFeedback: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Fasting")
        }
        .task {
            await loadService()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ContentUnavailableView("Fasting unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let service, let profile = profiles.first {
            mainContent(service: service, profile: profile)
        } else {
            ProgressView()
                .task {
                    if profiles.isEmpty {
                        _ = ProfileService.currentOrCreate(modelContext: modelContext)
                    }
                }
        }
    }

    @ViewBuilder
    private func mainContent(service: FastingService, profile: UserProfile) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let state = service.state(at: now, profile: profile)
            let window = service.activeFastWindow(at: now, profile: profile)
            let elapsed = service.elapsedFasting(at: now, profile: profile)
            let remaining = service.remainingInFast(at: now, profile: profile)

            ScrollView {
                VStack(spacing: 24) {
                    fastingRing(state: state, elapsed: elapsed, remaining: remaining, window: window)

                    VStack(alignment: .leading, spacing: 8) {
                        labelRow("State", value: state == .fasting ? "Fasting" : "Eating")
                        if let window {
                            labelRow("Window", value: window.label.capitalized)
                            labelRow("Started", value: format(date: window.start))
                            if window.label != "manual" {
                                labelRow("Ends", value: format(date: window.end))
                            }
                        } else {
                            let next = service.nextWindow(after: now, profile: profile)
                            labelRow("Next fast", value: "\(next.label.capitalized) at \(format(date: next.start))")
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    manualControls(service: service, profile: profile, state: state, window: window)

                    if let actionFeedback {
                        Text(actionFeedback)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if state == .fasting, let window {
                        Button {
                            Task {
                                _ = await FastingLiveActivityController.start(window: window)
                            }
                        } label: {
                            Label("Pin to Lock Screen", systemImage: "lock.iphone")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingBreakSheet) {
            EarlyBreakSheet(service: service, profile: profile)
        }
        .sheet(isPresented: $showingManualEndSheet) {
            ManualEndSheet(service: service) { reason in
                actionFeedback = "Fast ended \(reason == nil ? "" : "(\(reason!))")"
            }
        }
    }

    /// Manual start/stop controls. Always visible. Identity-framed copy.
    @ViewBuilder
    private func manualControls(service: FastingService,
                                profile: UserProfile,
                                state: FastingState,
                                window: FastWindow?) -> some View {
        let manualOpen = service.hasManualFastInProgress(asOf: Date())
        let canStart = state == .eating && !manualOpen
        let canEnd = manualOpen || state == .fasting

        HStack(spacing: 12) {
            Button {
                Task {
                    do {
                        _ = try service.startManualFast(profile: profile)
                        actionFeedback = "Fast started."
                    } catch FastingError.alreadyFasting {
                        actionFeedback = "A fast is already in progress."
                    } catch {
                        actionFeedback = "Could not start fast: \(error.localizedDescription)"
                    }
                }
            } label: {
                Label("Start fast now", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)

            Button(role: .destructive) {
                if window != nil && !manualOpen {
                    showingBreakSheet = true
                } else {
                    showingManualEndSheet = true
                }
            } label: {
                Label("End fast now", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(!canEnd)
        }
    }

    @ViewBuilder
    private func fastingRing(state: FastingState, elapsed: TimeInterval, remaining: TimeInterval?, window: FastWindow?) -> some View {
        let progress: Double = {
            // Manual fasts have no scheduled end; show a 16h reference ring so
            // the user gets a meaningful visual without divide-by-near-zero.
            if window?.label == "manual" {
                let referenceTotal: TimeInterval = 16 * 3600
                return min(1.0, max(0.0, elapsed / referenceTotal))
            }
            guard let window else { return 0 }
            let total = window.end.timeIntervalSince(window.start)
            return total > 0 ? min(1.0, max(0.0, elapsed / total)) : 0
        }()

        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(state == .fasting ? Color.accentColor : Color.gray,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)

            VStack(spacing: 4) {
                Text(state == .fasting ? "Fasting" : "Eating")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if state == .fasting, let remaining {
                    Text(formatDuration(remaining))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(formatDuration(elapsed))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("elapsed today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 240, height: 240)
        .padding(.top, 16)
    }

    private func labelRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    private func loadService() async {
        do {
            let config = try ScheduleConfigLoader.loadCached()
            service = FastingService(modelContext: modelContext, defaults: config.fastingDefaults)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }
}

private struct ManualEndSheet: View {
    let service: FastingService
    let onConfirm: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Optional note") {
                    TextField("Why end now? (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Text("Manual end logs your fast right now without judgement. Honest data > inflated streaks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("End fast")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("End now") {
                        let reason = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        _ = try? service.endManualFast(reason: reason.isEmpty ? nil : reason)  // MARK: try? justified - best-effort; failure logged inside the called function.
                        Task { await FastingLiveActivityController.endAll() }
                        onConfirm(reason.isEmpty ? nil : reason)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct EarlyBreakSheet: View {
    let service: FastingService
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason = "Hunger"
    @State private var customReason = ""

    private let presetReasons = ["Hunger", "Social meal", "Travel", "Sick", "Custom"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Reason") {
                    Picker("Why are you breaking the fast?", selection: $selectedReason) {
                        ForEach(presetReasons, id: \.self) { reason in
                            Text(reason).tag(reason)
                        }
                    }
                    if selectedReason == "Custom" {
                        TextField("Describe", text: $customReason, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                Section {
                    Button("Confirm break") {
                        confirm()
                    }
                }
            }
            .navigationTitle("End fast early")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func confirm() {
        let reason = selectedReason == "Custom" && !customReason.isEmpty ? customReason : selectedReason
        // try? justified: SwiftData write to local container; on the rare
        // failure we still want the sheet to dismiss and the user to see
        // unchanged state. Errors logged inside the service.
        try? service.logEarlyBreak(at: Date(), reason: reason, profile: profile)  // MARK: try? justified - best-effort; failure logged inside the called function.
        Task { await FastingLiveActivityController.endAll() }
        dismiss()
    }
}

#Preview {
    let schema = AppSchema.schema()
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let profile = UserProfile(name: "Clay", dob: Date(timeIntervalSince1970: 764985600), sex: "male")
    container.mainContext.insert(profile)
    return FastingView().modelContainer(container)
}
