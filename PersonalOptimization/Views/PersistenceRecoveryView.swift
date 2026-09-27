import SwiftUI

/// Blocking screen for a failed disk-store open. Never offers a reset/delete:
/// existing data must remain available for a corrected migration.
struct PersistenceRecoveryView: View {
    let reason: String
    var diagnostics: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Couldn't open your data")
                    .font(.title2.bold())

                Text(reason)
                    .foregroundStyle(.secondary)

                Text("If reopening the app did not help, install the next update without deleting the app. Keep this installation so your saved data can be recovered.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !diagnostics.isEmpty {
                    ShareLink(item: diagnostics) {
                        Label("Share startup report", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("persistence.shareReport")

                    Text("The report includes app and system versions and error codes. It does not include your health or workout records.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PersistenceRecoveryView(
        reason: "The database could not be opened. The app has not erased or reset your saved data.",
        diagnostics: "Preview startup report"
    )
}
