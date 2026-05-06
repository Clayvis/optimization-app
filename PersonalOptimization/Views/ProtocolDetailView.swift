import SwiftUI

struct ProtocolDetailView: View {
    let tally: ProtocolAdherenceTally
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(tally.displayText)
                        .font(.title3.weight(.semibold))
                }

                Section("Per-domain detail") {
                    ForEach(tally.domains) { domain in
                        domainRow(domain)
                    }
                }
            }
            .navigationTitle("Today's Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func domainRow(_ domain: ProtocolDomainResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: domain))
                .foregroundStyle(domain.completed ? Color.green : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(domain.label)
                    .font(.body.weight(.medium))
                Text(domain.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !domain.scheduled {
                Text("Not scheduled")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if domain.completed {
                Text("Done")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text("Open")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func icon(for domain: ProtocolDomainResult) -> String {
        if domain.completed { return "checkmark.circle.fill" }
        if !domain.scheduled { return "minus.circle" }
        return "circle"
    }
}
