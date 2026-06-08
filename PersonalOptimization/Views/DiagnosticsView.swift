import SwiftUI
import SwiftData
import HealthKit
import OSLog

/// Settings -> Diagnostics. Surfaces persistence + integration health for the user
/// (HK auth, recent HK failures, API key state, token usage today / this month, and
/// a "Test API key" affordance). Read-only outputs; the only writes are explicit
/// user actions (test, clear failures).
@MainActor
struct DiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\HealthKitWriteFailure.timestamp, order: .reverse)])
    private var failures: [HealthKitWriteFailure]
    @Query(sort: [SortDescriptor(\CoachInsight.generatedAt, order: .reverse)])
    private var insights: [CoachInsight]
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor(\BackgroundTaskLog.startedAt, order: .reverse)])
    private var backgroundTasks: [BackgroundTaskLog]

    @State private var hkWorkoutAuth: HKAuthorizationStatus = .notDetermined
    @State private var hkWaterAuth: HKAuthorizationStatus = .notDetermined
    @State private var apiKeyStatus: APIKeyStatus = .unknown
    @State private var apiKeyStoragePosture: KeyStoragePosture?
    @State private var apiKeyTestResult: String?
    @State private var testInFlight = false
    @State private var hkSyncService: HealthKitSyncService?
    @State private var rollupInFlight = false
    @State private var rollupResult: String?
    @State private var logExportURL: URL?
    @State private var logExportInFlight = false
    @State private var metrics: EngagementMetrics?

    enum APIKeyStatus { case unknown, set, missing }

    var body: some View {
        Form {
            schemaSection
            instrumentationSection
            healthKitSection
            apiKeySection
            tokenUsageSection
            backgroundTasksSection
            failuresSection
            exportLogsSection
        }
        .navigationTitle("Diagnostics")
        .onAppear {
            refresh()
            if hkSyncService == nil {
                hkSyncService = HealthKitSyncService(modelContext: modelContext)
            }
            try? AchievementService(modelContext: modelContext).unlockImperative("diagnostics_clean")  // MARK: try? justified - best-effort; failure logged inside the called function.
        }
        .task { await computeMetrics() }
    }

    /// Recomputes the 30-day instrumentation snapshot. Pulls the partner's
    /// current streak from the shared zone when paired (nil for the single-user
    /// reality of v1.0) so the joint-streak indicator is correct.
    private func computeMetrics() async {
        let partnerStreak = (try? await PartnerService(modelContext: modelContext).partnerSnapshot())?.currentStreak
        metrics = EngagementMetricsService(modelContext: modelContext).compute(partnerCurrentStreak: partnerStreak)
    }

    @ViewBuilder
    private var schemaSection: some View {
        Section("Persistence") {
            let v = AppSchema.current.versionIdentifier
            HStack {
                Text("Schema version")
                Spacer()
                Text("\(v.major).\(v.minor).\(v.patch)").monospacedDigit().font(.caption)
            }
        }
    }

    @ViewBuilder
    private var instrumentationSection: some View {
        Section {
            if let m = metrics {
                metricRow("Days since first launch", "\(m.daysSinceFirstLaunch)")

                // 1. 7-day streak establishment (primary success metric).
                metricRow(
                    "7-day streak",
                    establishmentText(m),
                    tint: m.establishedInWeekOne ? .green : (m.establishedSevenDayStreak ? .orange : .secondary)
                )

                // 2. Day-over-day return rate (local CURR).
                metricRow(
                    "Day-over-day return",
                    m.dayOverDayReturnRate.map { "\(Int(($0 * 100).rounded()))% · \(m.activeDaysCount) active days" } ?? "not enough data",
                    tint: (m.dayOverDayReturnRate ?? 0) >= 0.5 ? .green : .secondary
                )

                // 3. Grace-day usage.
                metricRow(
                    "Grace days used",
                    graceText(m)
                )

                // 4. Joint-streak survival.
                metricRow(
                    "Joint streak",
                    m.partnerPaired ? "joint \(m.jointStreak ?? 0) · solo \(m.soloStreak)" : "no partner paired"
                )

                // 5. Insight engagement.
                metricRow(
                    "Insight engagement",
                    insightText(m),
                    tint: m.insightsShown == 0 ? .secondary : (m.meetsInsightGate ? .green : .orange)
                )

                // 6. Qualitative week-4 check.
                week4Row(m)
            } else {
                ProgressView()
            }
        } header: {
            Text("Test instrumentation (30-day)")
        } footer: {
            Text("Leading indicators that predict retention, computed on-device from your own data. Primary target: establish a 7-day streak in week one. Freeze pools are per domain.")
        }
    }

    private func metricRow(_ label: String, _ value: String, tint: Color = .secondary) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(tint)
        }
    }

    private func establishmentText(_ m: EngagementMetrics) -> String {
        if m.establishedInWeekOne { return "established in week one ✓" }
        if m.establishedSevenDayStreak {
            if let d = m.daysToEstablishment { return "established (day \(d))" }
            return "established"
        }
        if m.anyDomainReachedSeven { return "a domain hit 7, protocol not yet" }
        return "not yet"
    }

    private func graceText(_ m: EngagementMetrics) -> String {
        let remaining = "\(m.freezesRemainingThisMonth) freezes left"
        guard m.graceDaysApplied > 0 else { return "0 · \(remaining)" }
        let breakdown = m.graceBySource
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        return "\(m.graceDaysApplied) days (\(breakdown)) · \(remaining)"
    }

    private func insightText(_ m: EngagementMetrics) -> String {
        guard m.insightsShown > 0 else { return "none shown yet" }
        let rate = m.insightInteractionRate.map { "\(Int(($0 * 100).rounded()))% engaged" } ?? "—"
        let gate = m.meetsInsightGate ? "gate ✓" : "gate ✗"
        return "\(m.insightsShown) shown · \(rate) · \(m.insightHelpful)↑/\(m.insightUnhelpful)↓ · \(gate)"
    }

    @ViewBuilder
    private func week4Row(_ m: EngagementMetrics) -> some View {
        if m.week4Captured {
            metricRow(
                "Week-4 check",
                (m.week4FeelsMotivating ?? false) ? "still motivating ✓" : "feels like an obligation",
                tint: (m.week4FeelsMotivating ?? false) ? .green : .orange
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Does this still feel motivating, or like an obligation?")
                    .font(.subheadline)
                HStack {
                    Button("Still motivating") { recordWeek4(true) }
                        .buttonStyle(.borderedProminent)
                    Button("Feels like an obligation") { recordWeek4(false) }
                        .buttonStyle(.bordered)
                }
                .font(.caption)
            }
            .padding(.vertical, 2)
        }
    }

    private func recordWeek4(_ motivating: Bool) {
        Week4CheckIn.record(feelsMotivating: motivating)
        Task { await computeMetrics() }
    }

    @ViewBuilder
    private var backgroundTasksSection: some View {
        Section("Background tasks") {
            let recent = backgroundTasks.prefix(5)
            if recent.isEmpty {
                Text("No background tasks recorded yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                let failureCount = backgroundTasks.prefix(30).filter { $0.status == "failure" || $0.status == "expired" }.count
                if failureCount > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("\(failureCount) failed runs in the last 30 logged")
                            .font(.footnote.weight(.medium))
                    }
                }
                ForEach(Array(recent), id: \.persistentModelID) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(formatTimestamp(task.startedAt))
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(task.status)
                                .font(.caption)
                                .foregroundStyle(taskStatusColor(task.status))
                        }
                        if let summary = task.summary {
                            Text(summary).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let err = task.errorMessage {
                            Text(err).font(.caption2).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func taskStatusColor(_ status: String) -> Color {
        switch status {
        case "success": return .green
        case "failure", "expired": return .red
        case "running": return .orange
        default: return .secondary
        }
    }

    @ViewBuilder
    private var healthKitSection: some View {
        Section("HealthKit") {
            statusRow(label: "Workouts (write)", status: hkWorkoutAuth)
            statusRow(label: "Water (write)", status: hkWaterAuth)
            if let svc = hkSyncService {
                HStack {
                    Text("Last sync")
                    Spacer()
                    if svc.isSyncing {
                        ProgressView().controlSize(.small)
                    } else if let when = svc.lastSyncedAt {
                        Text(formatTimestamp(when))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("never")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let ms = svc.lastSyncDurationMs {
                    HStack {
                        Text("Last duration")
                        Spacer()
                        Text("\(ms) ms").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let err = svc.lastSyncError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
            }
            Button {
                Task { await runRollupNow() }
            } label: {
                HStack {
                    Label("Run rollup now", systemImage: "arrow.clockwise")
                    if rollupInFlight {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(rollupInFlight)
            if let rollupResult {
                Text(rollupResult).font(.caption).foregroundStyle(rollupResult.hasPrefix("OK") ? .green : .red)
            }
        }
    }

    @ViewBuilder
    private var exportLogsSection: some View {
        Section("Logs") {
            Button {
                Task { await exportLogs() }
            } label: {
                HStack {
                    Label("Export last 24h of logs", systemImage: "square.and.arrow.up")
                    if logExportInFlight {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(logExportInFlight)
            if let url = logExportURL {
                ShareLink(item: url) {
                    Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up.fill")
                }
            }
        }
    }

    private func runRollupNow() async {
        guard let svc = hkSyncService else { return }
        rollupInFlight = true
        defer { rollupInFlight = false }
        await svc.syncRange(days: 7)
        rollupResult = "OK · synced last 7 days"
    }

    private func exportLogs() async {
        logExportInFlight = true
        defer { logExportInFlight = false }
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let oneDayAgo = store.position(date: Date().addingTimeInterval(-86_400))
            let predicate = NSPredicate(format: "subsystem == %@", BuildConfig.loggingSubsystem)
            let entries = try store.getEntries(with: [], at: oneDayAgo, matching: predicate)
            var lines: [String] = []
            for case let entry as OSLogEntryLog in entries {
                let ts = ISO8601DateFormatter().string(from: entry.date)
                lines.append("\(ts) [\(entry.category)] \(entry.composedMessage)")
            }
            let body = lines.joined(separator: "\n")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("PersonalOptimization-logs-\(Int(Date().timeIntervalSince1970)).txt")
            try body.data(using: .utf8)?.write(to: url)
            logExportURL = url
        } catch {
            logExportURL = nil
        }
    }

    private func statusRow(label: String, status: HKAuthorizationStatus) -> some View {
        HStack {
            Text(label)
            Spacer()
            Circle()
                .fill(color(for: status))
                .frame(width: 10, height: 10)
            Text(text(for: status))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func color(for status: HKAuthorizationStatus) -> Color {
        switch status {
        case .sharingAuthorized: return .green
        case .sharingDenied: return .red
        case .notDetermined: return .gray
        @unknown default: return .gray
        }
    }

    private func text(for status: HKAuthorizationStatus) -> String {
        switch status {
        case .sharingAuthorized: return "Authorized"
        case .sharingDenied: return "Denied"
        case .notDetermined: return "Not requested"
        @unknown default: return "Unknown"
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        Section("API key") {
            HStack {
                Text("Status")
                Spacer()
                Text(apiKeyStatusText)
                    .font(.caption)
                    .foregroundStyle(apiKeyStatus == .set ? .green : .red)
            }
            if let posture = apiKeyStoragePosture {
                HStack {
                    Text("Storage")
                    Spacer()
                    Text(posture.displayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let lastInsight = insights.first {
                HStack {
                    Text("Last successful call")
                    Spacer()
                    Text(formatTimestamp(lastInsight.generatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await testKey() }
            } label: {
                HStack {
                    Label("Test API key", systemImage: "checkmark.seal")
                    if testInFlight {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(testInFlight || apiKeyStatus != .set)
            if let apiKeyTestResult {
                Text(apiKeyTestResult)
                    .font(.footnote)
                    .foregroundStyle(apiKeyTestResult.hasPrefix("OK") ? .green : .red)
            }
        }
    }

    @ViewBuilder
    private var tokenUsageSection: some View {
        Section("Token usage") {
            let budget = TokenBudgetService.forUser(modelContext: modelContext)
            let today = budget.spentToday()
            let month = budget.spentThisMonth()
            let dailyCap = budget.dailyBudget
            HStack {
                Text("Today")
                Spacer()
                if dailyCap > 0 {
                    Text("\(today) / \(dailyCap)").monospacedDigit()
                } else {
                    Text("AI disabled").foregroundStyle(.secondary).font(.caption)
                }
            }
            if dailyCap > 0 {
                ProgressView(value: Double(min(today, dailyCap)), total: Double(dailyCap))
                    .tint(today >= dailyCap ? .red : (today > dailyCap * 80 / 100 ? .orange : .green))
            }
            HStack {
                Text("This month")
                Spacer()
                Text("\(month)").monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var failuresSection: some View {
        Section("Recent HealthKit write failures") {
            if failures.isEmpty {
                Text("No recent failures.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(failures.prefix(10), id: \.persistentModelID) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(formatTimestamp(failure.timestamp))
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("attempt \(failure.retryCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(failure.errorDescription)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 2)
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

    private func refresh() {
        if HKHealthStore.isHealthDataAvailable() {
            let store = HKHealthStore()
            hkWorkoutAuth = store.authorizationStatus(for: HKObjectType.workoutType())
            hkWaterAuth = store.authorizationStatus(for: HKQuantityType(.dietaryWater))
        }
        do {
            let key = try KeychainService.shared.getApiKey()
            apiKeyStatus = key.isEmpty ? .missing : .set
        } catch {
            apiKeyStatus = .missing
        }
        apiKeyStoragePosture = KeychainService.shared.apiKeySyncPosture()
    }

    private func testKey() async {
        guard !testInFlight else { return }
        testInFlight = true
        defer { testInFlight = false }
        let model = profiles.first?.anthropicModel ?? "claude-haiku-4-5-20251001"
        do {
            let response = try await ClaudeAPIClient.shared.complete(
                model: model,
                systemPrompt: "Reply with only the word 'pong'.",
                userPrompt: "ping",
                maxTokens: 16
            )
            let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            apiKeyTestResult = "OK · \(trimmed) · \(response.totalTokens) tokens"
        } catch {
            apiKeyTestResult = "Failed · \(error.localizedDescription)"
        }
    }

    private enum TimeRange { case startOfToday, startOfMonth }

    private func tokenSum(within range: TimeRange) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let now = Date()
        let cutoff: Date = {
            switch range {
            case .startOfToday:
                return cal.startOfDay(for: now)
            case .startOfMonth:
                return cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            }
        }()
        return insights.filter { $0.generatedAt >= cutoff }.map(\.tokenUsage).reduce(0, +)
    }

    private func formatTimestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone.current
        f.dateFormat = "MMM d HH:mm"
        return f.string(from: d)
    }
}
