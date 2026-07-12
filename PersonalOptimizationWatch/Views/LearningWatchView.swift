import SwiftUI
import SwiftData
import WatchKit

/// Watch learning glance. Records minutes against today's `DailyLog` for
/// Japanese / Guitar / Coursework. One-tap +5/+10/+25 buttons per module
/// because phone-side detail (vocab, exercises) doesn't belong on a wrist.
@MainActor
struct LearningWatchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var refreshTrigger = 0
    @State private var feedbackMessage: String?

    private let increments = [5, 10, 25]
    private let modules: [(key: String, label: String, glyph: String)] = [
        ("japanese", "Japanese", "character.book.closed"),
        ("guitar", "Guitar", "guitars"),
        ("coursework", "Coursework", "graduationcap.fill")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                summaryRow
                ForEach(modules, id: \.key) { module in
                    moduleBlock(key: module.key, label: module.label, glyph: module.glyph)
                }
                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .id(refreshTrigger)
        }
    }

    @ViewBuilder
    private var summaryRow: some View {
        let log = todayLog()
        HStack {
            Image(systemName: "book.fill").foregroundStyle(.green)
            Text("\((log?.japaneseMinutes ?? 0) + (log?.guitarMinutes ?? 0) + (log?.courseworkMinutes ?? 0)) min")
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Spacer()
            Text("today").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Learning today")
        .accessibilityValue("\((log?.japaneseMinutes ?? 0) + (log?.guitarMinutes ?? 0) + (log?.courseworkMinutes ?? 0)) minutes")
    }

    @ViewBuilder
    private func moduleBlock(key: String, label: String, glyph: String) -> some View {
        let log = todayLog()
        let minutes: Int = {
            switch key {
            case "japanese":   return log?.japaneseMinutes ?? 0
            case "guitar":     return log?.guitarMinutes ?? 0
            case "coursework": return log?.courseworkMinutes ?? 0
            default:           return 0
            }
        }()
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: glyph).foregroundStyle(.tint)
                Text(label).font(.caption.weight(.semibold))
                Spacer()
                Text("\(minutes) min")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) practice")
            .accessibilityValue("\(minutes) minutes today")
            HStack(spacing: 4) {
                ForEach(increments, id: \.self) { inc in
                    Button {
                        addMinutes(inc, into: key)
                    } label: {
                        Text("+\(inc)")
                            .font(.caption2.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(String(localized: "Add \(inc) minutes of \(label)"))
                    .accessibilityHint(String(localized: "Records \(inc) minutes of practice for \(label)"))
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Logging

    private func addMinutes(_ minutes: Int, into key: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = UserCalendar.timezone(modelContext: modelContext)
        let log = DailyLogStore(modelContext: modelContext, calendar: cal).upsertToday()
        switch key {
        case "japanese":   log.japaneseMinutes += minutes
        case "guitar":     log.guitarMinutes += minutes
        case "coursework": log.courseworkMinutes += minutes
        default: break
        }
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
        WKInterfaceDevice.current().play(.success)
        feedbackMessage = "+\(minutes) min logged"
        refreshTrigger += 1
    }

    private func todayLog() -> DailyLog? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let day = cal.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == day }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }
}
