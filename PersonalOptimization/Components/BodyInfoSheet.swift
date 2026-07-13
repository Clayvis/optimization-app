import SwiftUI
import SwiftData

/// Modal wrapper around `BodyInfoForm` for the Today prompt (profiles created
/// before the onboarding body step existed). Drafts locally; writes to the
/// profile only on Save.
struct BodyInfoSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var dob: Date = Calendar.current.date(from: DateComponents(year: 1995, month: 1, day: 1)) ?? Date()
    @State private var sex: String = "male"
    @State private var heightInches: Double = 70
    @State private var weightLbs: Double = 180
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Body") {
                    BodyInfoForm(
                        dob: $dob,
                        sex: $sex,
                        heightInches: $heightInches,
                        weightLbs: $weightLbs
                    )
                }
                Section {
                    Text("Powers calorie estimates for phone-only workouts, biological-age math, and Coach context. Stays on your devices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .task { seedFromProfile() }
        }
    }

    private func seedFromProfile() {
        guard !loaded, let profile = profiles.first else { return }
        loaded = true
        if profile.dob != .distantPast { dob = profile.dob }
        sex = profile.sex
        heightInches = profile.heightInches
        weightLbs = profile.weightLbs
    }

    private func save() {
        guard let profile = profiles.first else {
            dismiss()
            return
        }
        profile.dob = dob
        profile.sex = sex
        profile.heightInches = heightInches
        profile.weightLbs = weightLbs
        try? modelContext.save()  // MARK: try? save() is best-effort — failures surface via os_log; in-memory state already updated.
        dismiss()
    }
}

#Preview {
    BodyInfoSheet()
}
