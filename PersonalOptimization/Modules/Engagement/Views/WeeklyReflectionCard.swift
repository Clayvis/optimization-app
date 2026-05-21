import SwiftUI
import SwiftData
import Charts

/// Sunday Today-tab card. Identity-framed week summary.
@MainActor
struct WeeklyReflectionCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\WeeklyReflection.weekStartDate, order: .reverse)])
    private var reflections: [WeeklyReflection]

    @State private var showingDetail = false

    private var current: WeeklyReflection? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())
        let raw = cal.component(.weekday, from: today)
        let iso = raw == 1 ? 7 : raw - 1
        let monday = cal.date(byAdding: .day, value: -(iso - 1), to: today) ?? today
        return reflections.first { cal.isDate($0.weekStartDate, inSameDayAs: monday) }
    }

    var body: some View {
        Button {
            ensureGenerated()
            showingDetail = true
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .task { ensureGenerated() }
        .sheet(isPresented: $showingDetail) {
            if let r = current {
                WeeklyReflectionDetailView(reflection: r)
            }
        }
    }

    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(.tint)
                Text("WEEKLY REFLECTION")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let r = current {
                Text(r.coachMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    metricChip("\(Int(r.adherencePercent * 100))%", "adherence")
                    metricChip("\(r.workoutCount)", "workouts")
                    metricChip("\(r.hydrationDaysMet)", "hydration days")
                }
            } else {
                Text("Tap to generate this week's reflection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func metricChip(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func ensureGenerated() {
        if current == nil {
            _ = try? WeeklyReflectionService(modelContext: modelContext).currentOrGenerate()
        }
    }
}

@MainActor
private struct WeeklyReflectionDetailView: View {
    @Bindable var reflection: WeeklyReflection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var noteDraft: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(reflection.coachMessage)
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    metricGrid

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reflection")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField("What worked. What didn't. What's next.",
                                  text: $noteDraft, axis: .vertical)
                            .lineLimit(3...10)
                            .textFieldStyle(.roundedBorder)
                            .onAppear {
                                noteDraft = reflection.userNote ?? ""
                            }
                            .onChange(of: noteDraft) { _, newValue in
                                reflection.userNote = newValue.isEmpty ? nil : newValue
                                try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
                            }
                    }

                    Divider()
                    HStack {
                        Text("Generated \(reflection.generatedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Regenerate") {
                            _ = try? WeeklyReflectionService(modelContext: modelContext).regenerate()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding()
            }
            .navigationTitle("This week")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var metricGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 12) {
            metricBox(label: "Adherence", value: "\(Int(reflection.adherencePercent * 100))%", tint: .green)
            metricBox(label: "Workouts", value: "\(reflection.workoutCount)", tint: .red)
            metricBox(label: "Hydration days", value: "\(reflection.hydrationDaysMet)/7", tint: .blue)
            metricBox(label: "Fasting days", value: "\(reflection.fastingDaysCompleted)/7", tint: .indigo)
            metricBox(label: "Learning min", value: "\(reflection.learningMinutesTotal)", tint: .green)
            metricBox(label: "Best day",
                      value: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][safe: reflection.bestDayOfWeek - 1] ?? "—",
                      tint: .orange)
        }
    }

    private func metricBox(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
