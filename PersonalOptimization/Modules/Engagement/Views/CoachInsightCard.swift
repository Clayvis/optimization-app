import SwiftUI
import SwiftData

/// CoachInsightCard sits below the master metric on TodayView. Identity-framed copy,
/// minimum friction, low-affordance refresh.
@MainActor
struct CoachInsightCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query(sort: [SortDescriptor(\CoachInsight.generatedAt, order: .reverse)])
    private var insights: [CoachInsight]
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var apiKeyMissing = false
    @State private var showingDetail = false
    @State private var refreshCount = 0
    @State private var viewVisibleSince: Date?
    @State private var feedbackTrigger = 0

    private var profile: UserProfile? { profiles.first }
    private var latest: CoachInsight? { insights.first }

    var body: some View {
        Button {
            // API key entry lives in Settings only. The card stays passive when key
            // is missing — no sheet from here. Tapping when an insight is present
            // opens the detail sheet.
            if !apiKeyMissing, latest != nil {
                showingDetail = true
            }
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .task { await loadIfNeeded() }
        .onAppear {
            // Re-check key status whenever the card appears so a Settings-side
            // change is reflected without restart.
            apiKeyMissing = !keychainHasApiKey()
            if !apiKeyMissing {
                Task { await loadIfNeeded() }
            }
        }
        .sheet(isPresented: $showingDetail, onDismiss: {
            // Treat closing the detail sheet as a "dismissed" signal — but only
            // when the user hasn't already given a stronger signal.
            if let latest, latest.userInteraction.precedence < CoachInsightInteraction.dismissed.precedence {
                latest.userInteraction = .dismissed
                try? modelContext.save()
            }
        }) {
            if let latest {
                CoachInsightDetailSheet(insight: latest)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: refreshCount)
        .sensoryFeedback(.selection, trigger: feedbackTrigger)
        .onAppear { startVisibilityTimer() }
        .onDisappear { viewVisibleSince = nil }
    }

    @ViewBuilder
    private func feedbackButtons(for insight: CoachInsight) -> some View {
        let current = insight.userInteraction
        HStack(spacing: 12) {
            Button {
                record(.markedHelpful, on: insight)
            } label: {
                Image(systemName: current == .markedHelpful ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.subheadline)
                    .foregroundStyle(current == .markedHelpful ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark insight helpful")

            Button {
                record(.markedUnhelpful, on: insight)
            } label: {
                Image(systemName: current == .markedUnhelpful ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.subheadline)
                    .foregroundStyle(current == .markedUnhelpful ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark insight unhelpful")
        }
    }

    private func record(_ interaction: CoachInsightInteraction, on insight: CoachInsight) {
        // Toggle off if same button tapped twice; otherwise overwrite.
        if insight.userInteraction == interaction {
            insight.userInteraction = .viewed
        } else {
            insight.userInteraction = interaction
        }
        try? modelContext.save()
        feedbackTrigger &+= 1
    }

    /// Starts a 1.5s window. If the card stays on screen the full duration,
    /// auto-mark `.viewed` (only if the row is currently `.ignored`, so we
    /// never demote a stronger signal).
    private func startVisibilityTimer() {
        viewVisibleSince = Date()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let started = viewVisibleSince,
                  Date().timeIntervalSince(started) >= 1.5,
                  let latest else { return }
            if latest.userInteraction == .ignored {
                latest.userInteraction = .viewed
                try? modelContext.save()
            }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.tint)
                Text("COACH")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .rotationEffect(loading ? .degrees(360) : .zero)
                        .animation(loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: loading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh coach insight")
                .disabled(loading || apiKeyMissing)
            }

            if apiKeyMissing {
                Text("Set your Anthropic API key in Settings to enable Coach Mode.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let latest {
                Text(latest.insightText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(timeAgo(latest.generatedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    feedbackButtons(for: latest)
                }
            } else if loading {
                ProgressView()
                    .controlSize(.small)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                Text("Today's insight is on the way.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var accessibilityLabel: String {
        if apiKeyMissing { return "Coach mode disabled. Set API key in Settings." }
        return latest?.insightText ?? "Coach insight loading"
    }

    private func loadIfNeeded(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let service = CoachService(modelContext: modelContext)
        do {
            _ = try await (force ? service.refresh() : service.todayInsight())
            errorMessage = nil
        } catch CoachServiceError.missingAPIKey {
            apiKeyMissing = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() async {
        await loadIfNeeded(force: true)
        refreshCount &+= 1
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

private struct CoachInsightDetailSheet: View {
    let insight: CoachInsight
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(insight.insightText)
                        .font(.title3)
                        .foregroundStyle(.primary)

                    Divider()

                    Text("CONTEXT")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(insight.contextSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Divider()

                    HStack {
                        Text("Tokens used: \(insight.tokenUsage)")
                        Spacer()
                        Text("Refreshes today: \(insight.refreshCount)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct APIKeyEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var error: String?
    let onSaved: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic API key") {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Text("Stored in iOS Keychain on this device only. Never synced.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("API key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        do {
            try KeychainService.shared.setApiKey(trimmed)
            onSaved(trimmed)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
