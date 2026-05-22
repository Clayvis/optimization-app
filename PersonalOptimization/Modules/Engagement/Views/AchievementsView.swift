import SwiftUI
import SwiftData

/// Settings → Achievements. Lists every achievement grouped by category;
/// unlocked rows show the unlock date, locked rows show the description with
/// a muted glyph. No score, no points, no extrinsic reward gimmicks — just
/// the named-win record.
@MainActor
struct AchievementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Achievement.unlockedAt, order: .reverse)])
    private var unlocked: [Achievement]

    private var unlockedByID: [String: Date] {
        Dictionary(uniqueKeysWithValues: unlocked.map { ($0.identifier, $0.unlockedAt) })
    }

    private var unlockedCount: Int { unlocked.count }
    private var totalCount: Int { AchievementRegistry.allAchievements.count }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "trophy.fill").foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(unlockedCount) of \(totalCount) unlocked")
                            .font(.body.weight(.semibold))
                        Text("Identity wins. No points, no leaderboard.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            ForEach(AchievementRegistry.groupedByCategory, id: \.category) { group in
                Section(group.category.displayName) {
                    ForEach(group.items, id: \.id) { def in
                        achievementRow(def)
                    }
                }
            }
        }
        .navigationTitle("Achievements")
        .task {
            // Re-evaluate on appear so any deltas surface immediately.
            _ = try? AchievementService(modelContext: modelContext).evaluate()  // MARK: try? justified - best-effort; failure logged inside the called function.
        }
    }

    @ViewBuilder
    private func achievementRow(_ def: AchievementDefinition) -> some View {
        let unlockedAt = unlockedByID[def.id]
        let isUnlocked = unlockedAt != nil
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: def.glyph)
                    .foregroundStyle(isUnlocked ? Color.accentColor : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(def.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                Text(def.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = unlockedAt {
                    Text("Unlocked \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isUnlocked {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }
}
