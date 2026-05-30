import SwiftUI

/// Blocking screen shown when the on-disk store could not be opened and the
/// app fell back to an in-memory recovery store (`PersistenceMode.recovery`).
///
/// Deliberately offers NO destructive action (no reset, no delete, no wipe):
/// the on-disk store and its iCloud copy are untouched and a clean relaunch is
/// the recovery path. Surfacing a "reset" button here would invite the user to
/// destroy recoverable data, violating the permanent-retention rule.
struct PersistenceRecoveryView: View {
    let reason: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Couldn't open your data")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(reason)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Force-quit the app (swipe it away in the app switcher) and reopen it. If it keeps happening, restart your device. Your data on this device and in iCloud has not been changed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PersistenceRecoveryView(
        reason: "The database could not be opened this launch. Your saved data has not been changed. Please close the app fully and reopen it."
    )
}
