import SwiftUI
import SwiftData

/// Settings → Partnership. Lets the user generate a pairing code or accept
/// one from their partner. v1 ships UI + state; the CloudKit shared zone
/// that actually moves data between Apple IDs is post-paid-dev work and is
/// disabled visibly so the user understands the limitation.
@MainActor
struct PartnerSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var enteredCode: String = ""
    @State private var feedback: String?
    @State private var showingUnpairConfirm = false

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Form {
            Section {
                Text("Couples who exercise together have a 6× lower 12-month dropout rate. Partner mode shares only the lighter signals — current streaks, today's master metric, mascot state — never your specific weights or notes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let profile, profile.partnerRecordID != nil {
                pairedSection(profile: profile)
            } else if let profile {
                generateSection(profile: profile)
                acceptSection(profile: profile)
            }

            Section {
                Label("Cross-device sync requires a paid Apple Developer membership. Until then, pairing state is local-only.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let feedback {
                Section {
                    Text(feedback).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Partnership")
        .confirmationDialog("Unpair from your partner?",
                            isPresented: $showingUnpairConfirm,
                            titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { unpair() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their shared data is removed from your device. Re-pairing requires a fresh code from either side.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func generateSection(profile: UserProfile) -> some View {
        Section("Generate a code for your partner") {
            if let code = PartnerService(modelContext: modelContext).activeCode(for: profile),
               let expires = profile.partnerPairingCodeExpiresAt {
                VStack(alignment: .leading, spacing: 6) {
                    Text(code)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("Expires \(expires.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Button("Generate a new code") { generate() }
                    .buttonStyle(.bordered)
            } else {
                Button {
                    generate()
                } label: {
                    Label("Generate code", systemImage: "person.2.badge.gearshape")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func acceptSection(profile: UserProfile) -> some View {
        Section("Or enter your partner's code") {
            TextField("ABC123", text: $enteredCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.title3, design: .rounded))
                .monospacedDigit()
            Button {
                accept(profile: profile)
            } label: {
                Label("Pair", systemImage: "person.2.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(enteredCode.trimmingCharacters(in: .whitespaces).count != 6)
        }
    }

    @ViewBuilder
    private func pairedSection(profile: UserProfile) -> some View {
        Section("Paired") {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Linked with partner")
                        .font(.body.weight(.semibold))
                    if let date = profile.partnerLinkedAt {
                        Text("Since \(date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Toggle("Share my data with partner", isOn: Binding(
                get: { profile.partnerOptedIntoSharing },
                set: { newValue in
                    profile.partnerOptedIntoSharing = newValue
                    try? modelContext.save()
                }
            ))
            Button(role: .destructive) {
                showingUnpairConfirm = true
            } label: {
                Label("Unpair", systemImage: "person.2.slash")
            }
        }
    }

    // MARK: - Actions

    private func generate() {
        guard let profile else { return }
        do {
            let code = try PartnerService(modelContext: modelContext).generatePairingCode(for: profile)
            feedback = "Code \(code) generated. Share it with your partner."
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func accept(profile: UserProfile) {
        let code = enteredCode.uppercased().trimmingCharacters(in: .whitespaces)
        do {
            // Until CloudKit shared zone wires up, we use a stub recordID equal
            // to the code itself. Post-paid-dev, the recordID will resolve to
            // the partner's actual iCloud user identifier.
            try PartnerService(modelContext: modelContext)
                .acceptCode(code, partnerRecordID: "stub:\(code)", on: profile)
            enteredCode = ""
            feedback = "Paired. Welcome to partner mode."
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func unpair() {
        guard let profile else { return }
        try? PartnerService(modelContext: modelContext).unpair(profile)
        feedback = "Unpaired."
    }
}
