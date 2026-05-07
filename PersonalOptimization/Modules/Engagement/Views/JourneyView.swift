import SwiftUI
import SwiftData

/// Self-comparison surface (V1 opp 5). Three layers:
///
/// 1. Year heat-map: 365 dots colored by master metric.
/// 2. Same-day-N-ago cards comparing today vs 30 / 90 / 365 days ago.
/// 3. Monthly retrospective on the first of the month.
///
/// Backed entirely by ActivityArchive rows already populated by the daily
/// rollup. No new data ingest.
@MainActor
struct JourneyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ActivityArchive.date, order: .forward)])
    private var archives: [ActivityArchive]

    private let timezone = TimeZone(identifier: "Asia/Tokyo") ?? .current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if archives.count >= 30 {
                        sameDayAgoCard
                        yearHeatmap
                    } else {
                        cleanStartCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .navigationTitle("Journey")
        }
    }

    // MARK: - Year heatmap

    @ViewBuilder
    private var yearHeatmap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST 365 DAYS")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text("Each square is a day. Greener = closer to your protocol.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            heatmapGrid
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var heatmapGrid: some View {
        let cal = jstCalendar()
        let today = cal.startOfDay(for: Date())
        // 53 columns × 7 rows so a year fits cleanly.
        let columns = 53
        let rows = 7
        let cellSize: CGFloat = 7
        let spacing: CGFloat = 2

        let archiveByDay: [Date: ActivityArchive] = Dictionary(
            uniqueKeysWithValues: archives.map { (cal.startOfDay(for: $0.date), $0) }
        )
        // Build a 53x7 grid where cell (col, row) is "today minus N days" for
        // some N. Newest column on the right.
        let total = columns * rows  // 371
        let startOffset = total - 1

        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { col in
                        let dayOffset = startOffset - (col * rows + row)
                        let day = cal.date(byAdding: .day, value: -dayOffset, to: today) ?? today
                        let metric = archiveByDay[cal.startOfDay(for: day)]?.masterMetric ?? 0
                        Rectangle()
                            .fill(heatColor(for: metric))
                            .frame(width: cellSize, height: cellSize)
                            .cornerRadius(1.5)
                    }
                }
            }
        }
    }

    private func heatColor(for metric: Double) -> Color {
        // 0 → muted gray; 1 → saturated green. Transparent strip for "no data."
        if metric <= 0 { return Color.gray.opacity(0.18) }
        let clamped = min(1.0, metric)
        return Color.green.opacity(0.25 + clamped * 0.65)
    }

    // MARK: - Same-day cards

    @ViewBuilder
    private var sameDayAgoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.tint)
                Text("YOU vs YOU")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            ForEach([30, 90, 365], id: \.self) { ago in
                comparisonRow(daysAgo: ago)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func comparisonRow(daysAgo: Int) -> some View {
        let cal = jstCalendar()
        let today = cal.startOfDay(for: Date())
        let pastDay = cal.date(byAdding: .day, value: -daysAgo, to: today) ?? today

        let todayMetric = archives.first(where: { cal.isDate($0.date, inSameDayAs: today) })?.masterMetric
        let pastMetric = archives.first(where: { cal.isDate($0.date, inSameDayAs: pastDay) })?.masterMetric

        VStack(alignment: .leading, spacing: 4) {
            Text(label(for: daysAgo))
                .font(.subheadline.weight(.semibold))
            HStack {
                comparisonChip(label: "Then", metric: pastMetric)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                comparisonChip(label: "Now", metric: todayMetric)
                Spacer()
                deltaText(then: pastMetric, now: todayMetric)
            }
        }
        .padding(.vertical, 4)
    }

    private func label(for daysAgo: Int) -> String {
        switch daysAgo {
        case 30:  return "One month ago"
        case 90:  return "Three months ago"
        case 365: return "One year ago"
        default:  return "\(daysAgo) days ago"
        }
    }

    @ViewBuilder
    private func comparisonChip(label: String, metric: Double?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(metric.map { "\(Int($0 * 100))%" } ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func deltaText(then: Double?, now: Double?) -> some View {
        if let t = then, let n = now {
            let delta = n - t
            let sign = delta >= 0 ? "+" : ""
            Text("\(sign)\(Int(delta * 100))%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(delta >= 0 ? .green : .orange)
        } else {
            EmptyView()
        }
    }

    // MARK: - Clean start

    @ViewBuilder
    private var cleanStartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.tint)
                Text("YOUR JOURNEY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text("The year wheel and same-day comparisons unlock at 30 days of data. Right now: \(archives.count) day\(archives.count == 1 ? "" : "s") logged.")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Keep going. The story builds itself.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func jstCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
    }
}
