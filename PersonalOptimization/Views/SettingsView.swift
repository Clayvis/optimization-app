import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profiles.first {
                    profileForm(profile: profile)
                } else {
                    ProgressView()
                        .task {
                            _ = ProfileService.currentOrCreate(modelContext: modelContext)
                        }
                }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private func profileForm(profile: UserProfile) -> some View {
        @Bindable var profile = profile
        Form {
            Section("Profile") {
                LabeledContent("Name") {
                    TextField("Name", text: $profile.name)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Date of birth", selection: $profile.dob, displayedComponents: .date)
                Picker("Sex", selection: $profile.sex) {
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                }
                LabeledContent("Height (in)") {
                    TextField("74", value: $profile.heightInches, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Weight (lb)") {
                    TextField("205", value: $profile.weightLbs, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Time zone") {
                LabeledContent("IANA identifier", value: profile.timezone)
            }

            Section("Fasting window") {
                Stepper("Start hour: \(profile.fastWindowStartHour)", value: $profile.fastWindowStartHour, in: 0...23)
                Stepper("End hour: \(profile.fastWindowEndHour)", value: $profile.fastWindowEndHour, in: 0...23)
            }

            Section("Hydration") {
                LabeledContent("Bottle size (oz)") {
                    TextField("32", value: $profile.bottleSizeOz, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("AI") {
                Picker("Anthropic model", selection: $profile.anthropicModel) {
                    Text("Sonnet 4.6").tag("claude-sonnet-4-6")
                    Text("Opus 4.7").tag("claude-opus-4-7")
                    Text("Haiku 4.5").tag("claude-haiku-4-5-20251001")
                }
            }

            Section("Mascot") {
                Toggle("Show mascot", isOn: $profile.mascotEnabled)
                Toggle("Reduced motion", isOn: $profile.reducedMotion)
            }

            Section("Rollout") {
                Picker("Phase", selection: $profile.rolloutPhase) {
                    Text("Weeks 1-2 (training-day fast)").tag(1)
                    Text("Weeks 3+ (16:8 daily)").tag(2)
                }
            }
        }
    }
}

#Preview {
    let schema = Schema(versionedSchema: SchemaV1.self)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return SettingsView().modelContainer(container)
}
