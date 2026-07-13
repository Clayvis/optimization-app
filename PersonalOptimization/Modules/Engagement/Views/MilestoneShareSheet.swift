#if os(iOS)
import SwiftUI
import UIKit

/// Renders a milestone unlock as a 600×600 square shareable image and opens
/// the system share sheet (Messages, Mail, Photos, anywhere). No text, no
/// branding, no link, just the mascot + identity-framed line so the image
/// reads as a personal moment, not an ad.
@MainActor
struct MilestoneShareSheet: View {
    let milestone: Milestone
    let mascotVariant: String
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?
    @State private var presentingActivity = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                shareCardPreview
                    .frame(width: 280, height: 280)
                Text("Tap Share to send.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    presentingActivity = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("Share milestone")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await render() }
            .sheet(isPresented: $presentingActivity) {
                if let image = renderedImage {
                    ShareActivitySheet(items: [image])
                }
            }
        }
    }

    @ViewBuilder
    private var shareCardPreview: some View {
        ShareCardLayout(milestone: milestone, mascotVariant: mascotVariant)
    }

    @MainActor
    private func render() async {
        let layout = ShareCardLayout(milestone: milestone, mascotVariant: mascotVariant)
            .frame(width: 600, height: 600)
        let renderer = ImageRenderer(content: layout)
        renderer.scale = 2
        renderedImage = renderer.uiImage
    }
}

/// The composable visual layout. Reused by both the on-screen preview and
/// the offscreen ImageRenderer so what the user sees == what gets shared.
@MainActor
struct ShareCardLayout: View {
    let milestone: Milestone
    let mascotVariant: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 14) {
                Spacer()
                MascotView(state: milestone.mascotState, variant: mascotVariant)
                    .frame(maxWidth: 280, maxHeight: 280)
                Text(milestone.unlockTitle)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .foregroundStyle(.primary)
                Text(milestone.unlockBody)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .padding()
        }
    }
}

/// Thin wrapper around UIActivityViewController so we can present from
/// SwiftUI without a custom UIViewControllerRepresentable per call site.
struct ShareActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
