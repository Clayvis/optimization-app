import SwiftUI

/// Reusable ninja/samurai surfaces built on `Theme` tokens. Pure SwiftUI, no
/// assets. These are the building blocks every screen composes so the revamp
/// stays consistent and a future restyle is one-file-deep.

// MARK: - Background

/// The layered ink ground with a faint asanoha (hemp-leaf) lattice, the
/// traditional samurai-armor underlayment motif, drawn at low opacity so it
/// reads as texture, not decoration. Apply once at the root of a screen.
struct DojoBackground: View {
    var body: some View {
        ZStack {
            Theme.groundGradient.ignoresSafeArea()
            AsanohaPattern()
                .stroke(Theme.hairline, lineWidth: 0.6)
                .opacity(0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Paint the dojo ground behind a screen's content.
    func dojoBackground() -> some View {
        background(DojoBackground())
    }
}

/// A repeating asanoha (麻の葉) lattice as a vector `Shape`. Cheap to draw;
/// scales to any size. Used only as a faint background texture.
struct AsanohaPattern: Shape {
    var cell: CGFloat = 46

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let h = cell
        let w = cell * 0.8660254  // cos(30°): width of a flat-topped hex column
        var x: CGFloat = 0
        while x <= rect.width + w {
            var y: CGFloat = 0
            while y <= rect.height + h {
                let cx = x, cy = y
                // Six spokes from the cell center — the asanoha star.
                for i in 0..<6 {
                    let a = CGFloat(i) * .pi / 3
                    p.move(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: cx + cos(a) * h / 2, y: cy + sin(a) * h / 2))
                }
                y += h
            }
            x += w
        }
        return p
    }
}

// MARK: - Card

/// A raised lacquer panel: rounded fill, hairline inlay edge, soft shadow, and
/// an optional crimson "blade" accent rule down the leading edge.
struct DojoCard<Content: View>: View {
    var accent: Color?
    var padding: CGFloat = Theme.Space.l
    @ViewBuilder var content: () -> Content

    init(accent: Color? = nil, padding: CGFloat = Theme.Space.l, @ViewBuilder content: @escaping () -> Content) {
        self.accent = accent
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.inkRaised)
            )
            .overlay(alignment: .leading) {
                if let accent {
                    accent.frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .padding(.vertical, padding * 0.6)
                        .padding(.leading, 2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - Section header

/// A stamped-seal eyebrow: short kurenai rule, then uppercase tracked label.
struct SectionEyebrow: View {
    let title: String
    var tint: Color = Theme.kurenai

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(tint)
                .frame(width: 16, height: 3)
            Text(title.uppercased())
                .font(Theme.eyebrow)
                .tracking(1.6)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Crest ring (progress)

/// Circular progress ring with a gradient stroke and an optional centered
/// label. The master-metric / goal visual. `progress` is 0...1.
struct CrestRing<Center: View>: View {
    var progress: Double
    var gradient: AngularGradient = AngularGradient(
        colors: [Theme.kurenaiDeep, Theme.kurenai, Theme.kin],
        center: .center
    )
    var lineWidth: CGFloat = 10
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.inkSunken, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, progress)))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)
            center()
        }
    }
}

extension CrestRing where Center == EmptyView {
    init(progress: Double, lineWidth: CGFloat = 10) {
        self.init(progress: progress, lineWidth: lineWidth) { EmptyView() }
    }
}

// MARK: - Chips & buttons

/// A small stat capsule (icon + value) on the sunken fill.
struct StatChip: View {
    var systemImage: String
    var text: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: systemImage).font(.caption2)
            Text(text).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.inkSunken))
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Card surface modifier

extension View {
    /// The lacquer panel as a drop-in replacement for the ad-hoc
    /// `.background(Color(.secondarySystemBackground)) + .clipShape(...)`
    /// card pattern: rounded raised fill, hairline inlay, soft shadow.
    /// Content keeps its own padding; this only swaps the chrome.
    func dojoCardSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.inkRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

/// Primary CTA styled as a crimson blade.
struct BladeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.bladeGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Subtle press feedback for card-shaped tappables (tiles, module cards).
/// Scale is skipped under Reduce Motion; the dim alone carries the state.
struct DojoPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Theme.Space.l) {
            SectionEyebrow(title: "Today's Protocol")
            DojoCard(accent: Theme.kurenai) {
                HStack(spacing: Theme.Space.l) {
                    CrestRing(progress: 0.75) {
                        VStack(spacing: 0) {
                            Text("3").font(Theme.numeral(28))
                            Text("/4").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Discipline").font(Theme.numeral(22)).foregroundStyle(Theme.textPrimary)
                        HStack {
                            StatChip(systemImage: "flame.fill", text: "12d", tint: Theme.kin)
                            StatChip(systemImage: "drop.fill", text: "48oz", tint: Theme.ai)
                        }
                    }
                }
            }
            Button("End Fast") {}.buttonStyle(BladeButtonStyle())
        }
        .padding()
    }
    .dojoBackground()
    .preferredColorScheme(.dark)
}
