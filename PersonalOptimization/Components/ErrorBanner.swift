import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onDismiss: (() -> Void)?

    init(message: String, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text("Error: \(message)"))
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Dismiss error")
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }
}

#Preview {
    VStack(spacing: 12) {
        ErrorBanner(message: "Could not load schedule")
        ErrorBanner(message: "Long error message that wraps across multiple lines to test layout behavior") {}
    }
    .padding()
}
