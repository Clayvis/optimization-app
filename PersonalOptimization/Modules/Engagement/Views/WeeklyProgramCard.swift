import SwiftUI
import SwiftData

/// Sunday Today-tab card. Shows the active weekly program narrative + per-day
/// summary. Identity-framed copy, inline accept/modify/dismiss controls.
@MainActor
struct WeeklyProgramCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\WeeklyProgram.weekStartDate, order: .reverse)])
    private var programs: [WeeklyProgram]

    @State private var loading = false
    @State private var errorMessage: String?
    @State private var apiKeyMissing = false
    @State private var showingDetail = false

    private var current: WeeklyProgram? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())
        let raw = cal.component(.weekday, from: today)
        let iso = raw == 1 ? 7 : raw - 1
        let monday = cal.date(byAdding: .day, value: -(iso - 1), to: today) ?? today
        return programs.first(where: { cal.isDate($0.weekStartDate, inSameDayAs: monday) })
    }

    var body: some View {
        Button {
            if current != nil { showingDetail = true }
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            if let p = current {
                WeeklyProgramDetailSheet(program: p)
            }
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.tint)
                Text("THIS WEEK'S PROGRAM")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if loading {
                    ProgressView().controlSize(.small)
                }
            }
            if apiKeyMissing {
                Text("Set your Anthropic API key in Settings to enable weekly programming.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let p = current {
                if !p.coachNarrative.isEmpty {
                    Text(p.coachNarrative)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                }
                Text("Tap to see day-by-day plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                Text("No active weekly program. Generate this week's pass.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await generate() }
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

    private func generate() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let service = CoachService(modelContext: modelContext)
        do {
            _ = try await service.generateWeeklyProgrammingPass()
            errorMessage = nil
        } catch CoachServiceError.missingAPIKey {
            apiKeyMissing = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WeeklyProgramDetailSheet: View {
    let program: WeeklyProgram
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !program.coachNarrative.isEmpty {
                        Text(program.coachNarrative)
                            .font(.body)
                    }
                    Divider()
                    Text("Plan (raw)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(program.programJSON)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    HStack {
                        Text("Generated: \(program.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        Spacer()
                        Text("\(program.tokenUsage) tokens")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Weekly program")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
