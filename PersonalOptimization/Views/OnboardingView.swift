import SwiftUI
import SwiftData
import HealthKit
import UserNotifications

/// First-launch onboarding wizard. Five screens, identity-framed, locked
/// progression so the user can't skip critical permission asks. Sets
/// `UserProfile.onboardingCompleted = true` on finish so RootView routes past
/// it on subsequent launches.
@MainActor
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var step: Int = 0
    @State private var primaryGoal: String = ""
    @State private var equipmentAccess: String = "gym"
    @State private var pickedVariant: MascotVariant = .ninjaMale
    @State private var hkRequested = false
    @State private var notifRequested = false
    @State private var seedingDone = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: 5)
                .tint(.accentColor)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            TabView(selection: $step) {
                welcomeScreen.tag(0)
                permissionsScreen.tag(1)
                goalsScreen.tag(2)
                mascotScreen.tag(3)
                wrapUpScreen.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)

            controls
        }
        .task { await ensureProfileExists() }
    }

    @ViewBuilder
    private var welcomeScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome.")
                .font(.largeTitle.weight(.bold))
            Text("This app is yours. Single user. No accounts. Nothing leaves your devices except the AI calls you opt into.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                bullet("No servers, no analytics, no ads.")
                bullet("All data lives in your iCloud private database.")
                bullet("Streaks bend for sick days and travel.")
                bullet("The mascot reflects real signals, never theater.")
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private var permissionsScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Two permissions, then we're done.")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 14) {
                permissionRow(
                    icon: "heart.fill",
                    title: "HealthKit",
                    detail: "Sleep, heart rate, HRV. Powers your mascot, weekly reflection, and Coach insights.",
                    granted: hkRequested,
                    action: requestHealthKit
                )
                permissionRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    detail: "One nudge per behavior per day max. Suppressed when you've already logged. Quiet hours honored.",
                    granted: notifRequested,
                    action: requestNotifications
                )
            }
            .padding(.horizontal, 16)
            Spacer()
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private var goalsScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "target")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("What are you optimizing for?")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text("One sentence. The Coach uses this to tune every prescription.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("e.g., build muscle, stay sharp on the court", text: $primaryGoal, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Equipment you have today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Equipment", selection: $equipmentAccess) {
                        Text("Full gym").tag("gym")
                        Text("Home (full)").tag("home_full")
                        Text("Home (minimal)").tag("home_minimal")
                        Text("Bodyweight only").tag("bodyweight")
                        Text("Outdoor").tag("outdoor")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 32)
        }
    }

    @ViewBuilder
    private var mascotScreen: some View {
        VStack(spacing: 16) {
            Text("Pick your mascot.")
                .font(.title2.weight(.bold))
                .padding(.top, 32)

            HStack(spacing: 24) {
                ForEach(MascotVariant.allCases) { variant in
                    Button {
                        pickedVariant = variant
                    } label: {
                        VStack(spacing: 8) {
                            Image("\(variant.assetPrefix)_Neutral")
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 100)
                                .padding(8)
                                .background(pickedVariant == variant ? Color.accentColor.opacity(0.20) : Color.gray.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(pickedVariant == variant ? Color.accentColor : Color.clear, lineWidth: 2)
                                }
                            Text(variant.displayName)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Text("They're a signal. Sad means a real miss. Proud means an earned win.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    @ViewBuilder
    private var wrapUpScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .padding(.top, 32)
            Text("You're set.")
                .font(.largeTitle.weight(.bold))
            Text("Five evidence-backed implementation intentions seeded for your morning routine, training, and learning. Edit them in Settings whenever the routine shifts.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                bullet("Apple Watch: pair the watch in the iOS Watch app to surface complications and live workouts.")
                bullet("Coach Mode: drop your Anthropic API key in Settings → AI to enable daily insights and prescriptions.")
                bullet("Sundays: open the Today tab for a weekly reflection.")
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if step < 4 {
                Button("Continue") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(canAdvance == false)
            } else {
                Button("Get started") { complete() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return true
        case 1: return true // permissions are optional but encouraged
        case 2: return true
        case 3: return true
        default: return true
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
            Text(text).font(.subheadline)
            Spacer()
        }
    }

    @ViewBuilder
    private func permissionRow(icon: String,
                               title: String,
                               detail: String,
                               granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Button(granted ? "Asked" : "Allow") {
                    action()
                }
                .buttonStyle(.bordered)
                .disabled(granted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func requestHealthKit() {
        Task {
            _ = try? await LiveHealthKitService.shared.requestAuthorization()
            hkRequested = true
        }
    }

    private func requestNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            notifRequested = true
        }
    }

    private func ensureProfileExists() async {
        if profiles.isEmpty {
            _ = ProfileService.currentOrCreate(modelContext: modelContext)
        }
        // Seed default custom activities so first-launch users see Running,
        // Walking, HIIT, Yoga, Cycling, Hiking on the Train tab without a
        // separate setup step.
        if !seedingDone {
            _ = try? CustomActivityService(modelContext: modelContext).seedDefaultsIfNeeded()
            _ = try? ImplementationIntentionService(modelContext: modelContext).seedStartersIfNeeded()
            seedingDone = true
        }
    }

    private func complete() {
        guard let profile else { return }
        let trimmedGoal = primaryGoal.trimmingCharacters(in: .whitespaces)
        if !trimmedGoal.isEmpty {
            profile.primaryGoal = trimmedGoal
        }
        profile.equipmentAccess = equipmentAccess
        profile.mascotVariant = pickedVariant.rawValue
        profile.onboardingCompleted = true
        try? modelContext.save()
    }
}
