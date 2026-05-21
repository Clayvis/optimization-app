import SwiftUI
import SwiftData
import HealthKit

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

    enum APIKeyStatus { case unknown, set, missing }

    var body: some View {
        Form {
            schemaSection
            healthKitSection
            apiKeySection
            tokenUsageSection
            backgroundTasksSection
            failuresSection
        }
        .navigationTitle("Diagnostics")
        .onAppear {
            refresh()
            try? AchievementService(modelContext: modelContext).unlockImperative("diagnostics_clean")
        }
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
