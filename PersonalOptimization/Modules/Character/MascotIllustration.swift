import Foundation
import SwiftUI

/// Vector-drawn chibi ninja mascot, one rendering per character state.
///
/// This is the always-available art path: `MascotView` prefers the
/// `<Variant>_<State>` PNG from `MascotAssets.xcassets` when the user has
/// installed generated art, and falls back to this illustration otherwise.
/// Drawn entirely with `Canvas` paths per the character brief (charcoal gi,
/// cream face, one accent color, chibi proportions) and the design-system
/// rule that every motif is drawn in SwiftUI.
///
/// Deliberately dependency-free: no UIKit, no Theme, no SwiftData. It takes
/// the state as a raw string so the widget extension can render it without
/// compiling the model layer.
struct MascotIllustration: View {
    /// Accent pigments per mascot variant. Self-contained (no Theme import)
    /// so the widget and complication targets can compile this file alone.
    struct Palette: Sendable {
        let accent: Color
        let accentDeep: Color

        /// Kurenai crimson — ninja_male.
        static let ninjaMale = Palette(accent: rgb(0xE6394A), accentDeep: rgb(0x9E1B28))
        /// Murasaki violet — ninja_female.
        static let ninjaFemale = Palette(accent: rgb(0x8A6FC4), accentDeep: rgb(0x5E4494))

        /// Maps a `UserProfile.mascotVariant` raw value or an asset-name
        /// prefix ("NinjaFemale_Proud") to its palette. Unknown → male.
        static func forVariant(_ variant: String) -> Palette {
            let v = variant.lowercased()
            if v.contains("female") { return .ninjaFemale }
            return .ninjaMale
        }

        private static func rgb(_ value: UInt32) -> Color {
            Color(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0
            )
        }
    }

    /// CharacterState raw value ("neutral", "proud", ...). Unknown values
    /// render as neutral so a stale widget snapshot can never blank the art.
    let stateName: String
    var palette: Palette = .ninjaMale

    var body: some View {
        Canvas { context, size in
            MascotRenderer(state: stateName, palette: palette)
                .draw(in: &context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true) // callers attach state-aware labels
    }
}

/// All geometry lives in a 100×100 design space and scales to the Canvas.
/// Shape coordinates mirror the approved SVG prototype one-for-one.
private struct MascotRenderer {
    let state: String
    let palette: Palette
    typealias Palette = MascotIllustration.Palette

    // Ink constants from the prototype.
    private let gi = Color(red: 0x2E / 255.0, green: 0x31 / 255.0, blue: 0x38 / 255.0)
    private let giDark = Color(red: 0x23 / 255.0, green: 0x26 / 255.0, blue: 0x2C / 255.0)
    private let skin = Color(red: 0xF4 / 255.0, green: 0xE3 / 255.0, blue: 0xCB / 255.0)
    private let ink = Color(red: 0x1C / 255.0, green: 0x1E / 255.0, blue: 0x22 / 255.0)
    private let gold = Color(red: 0xD7 / 255.0, green: 0xA2 / 255.0, blue: 0x3B / 255.0)
    private let droplet = Color(red: 0x5C / 255.0, green: 0xA9 / 255.0, blue: 0xE8 / 255.0)
    private let mist = Color(red: 0x9A / 255.0, green: 0xA0 / 255.0, blue: 0xAB / 255.0)
    private let blush = Color(red: 0xE6 / 255.0, green: 0x78 / 255.0, blue: 0x6E / 255.0).opacity(0.35)

    // Eye anchor points.
    private let eyeLeftX: CGFloat = 41.5
    private let eyeRightX: CGFloat = 58.5
    private let eyeY: CGFloat = 39

    private var headTilt: Angle {
        switch state {
        case "disappointed": return .degrees(2.5)
        case "tired":        return .degrees(-3)
        default:             return .zero
        }
    }

    private var bodyShiftY: CGFloat {
        state == "disappointed" ? 1.2 : 0
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width, size.height) / 100
        // Center the square design space inside the canvas.
        context.translateBy(
            x: (size.width - 100 * scale) / 2,
            y: (size.height - 100 * scale) / 2
        )
        context.scaleBy(x: scale, y: scale)

        if state == "fasting" { drawAura(in: &context) }
        if state == "achievement" { drawSparks(in: &context) }

        drawBody(in: &context)
        drawHead(in: &context)

        switch state {
        case "thirsty": drawDroplet(in: &context)
        case "urgent":  drawExclamation(in: &context)
        case "tired":   drawZzz(in: &context)
        default: break
        }
    }

    // MARK: - Body

    private func drawBody(in context: inout GraphicsContext) {
        var body = context
        body.translateBy(x: 0, y: bodyShiftY)

        var torso = Path()
        torso.move(to: CGPoint(x: 34, y: 70))
        torso.addQuadCurve(to: CGPoint(x: 50, y: 62), control: CGPoint(x: 34, y: 62))
        torso.addQuadCurve(to: CGPoint(x: 66, y: 70), control: CGPoint(x: 66, y: 62))
        torso.addLine(to: CGPoint(x: 66, y: 82))
        torso.addQuadCurve(to: CGPoint(x: 50, y: 90), control: CGPoint(x: 66, y: 90))
        torso.addQuadCurve(to: CGPoint(x: 34, y: 82), control: CGPoint(x: 34, y: 90))
        torso.closeSubpath()
        body.fill(torso, with: .color(gi))

        if state == "fasting" {
            var lotus = Path()
            lotus.move(to: CGPoint(x: 36, y: 88))
            lotus.addQuadCurve(to: CGPoint(x: 64, y: 88), control: CGPoint(x: 50, y: 96))
            lotus.addQuadCurve(to: CGPoint(x: 50, y: 94.5), control: CGPoint(x: 64, y: 94))
            lotus.addQuadCurve(to: CGPoint(x: 36, y: 88), control: CGPoint(x: 36, y: 94))
            lotus.closeSubpath()
            body.fill(lotus, with: .color(giDark))
        } else {
            let legL = Path(roundedRect: CGRect(x: 40.5, y: 86, width: 8.4, height: 9.5), cornerRadius: 4.2)
            let legR = Path(roundedRect: CGRect(x: 51.1, y: 86, width: 8.4, height: 9.5), cornerRadius: 4.2)
            body.fill(legL, with: .color(giDark))
            body.fill(legR, with: .color(giDark))
        }

        var wrap = Path()
        wrap.move(to: CGPoint(x: 43.5, y: 64))
        wrap.addLine(to: CGPoint(x: 56.5, y: 78))
        body.stroke(wrap, with: .color(giDark), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

        let belt = Path(roundedRect: CGRect(x: 35.5, y: 76.5, width: 29, height: 5.2), cornerRadius: 2.6)
        body.fill(belt, with: .color(palette.accent))
        let knot = Path(roundedRect: CGRect(x: 46.6, y: 75.6, width: 6.8, height: 7), cornerRadius: 2.2)
        body.fill(knot, with: .color(palette.accentDeep))

        drawArms(in: &body)
    }

    private func drawArms(in context: inout GraphicsContext) {
        let style = StrokeStyle(lineWidth: 7.5, lineCap: .round)
        var left = Path()
        var right = Path()
        let handL: CGPoint
        let handR: CGPoint

        switch state {
        case "proud", "achievement":
            left.move(to: CGPoint(x: 38, y: 74))
            left.addQuadCurve(to: CGPoint(x: 23, y: 57), control: CGPoint(x: 27, y: 68))
            right.move(to: CGPoint(x: 62, y: 74))
            right.addQuadCurve(to: CGPoint(x: 77, y: 57), control: CGPoint(x: 73, y: 68))
            handL = CGPoint(x: 22.4, y: 55.5)
            handR = CGPoint(x: 77.6, y: 55.5)
        case "urgent":
            left.move(to: CGPoint(x: 38, y: 74))
            left.addQuadCurve(to: CGPoint(x: 21.5, y: 62), control: CGPoint(x: 26, y: 71))
            right.move(to: CGPoint(x: 62, y: 74))
            right.addQuadCurve(to: CGPoint(x: 78.5, y: 62), control: CGPoint(x: 74, y: 71))
            handL = CGPoint(x: 21, y: 60.5)
            handR = CGPoint(x: 79, y: 60.5)
        case "disappointed", "tired":
            left.move(to: CGPoint(x: 39, y: 74))
            left.addQuadCurve(to: CGPoint(x: 32.5, y: 86), control: CGPoint(x: 33.5, y: 79))
            right.move(to: CGPoint(x: 61, y: 74))
            right.addQuadCurve(to: CGPoint(x: 67.5, y: 86), control: CGPoint(x: 66.5, y: 79))
            handL = CGPoint(x: 32.4, y: 87.5)
            handR = CGPoint(x: 67.6, y: 87.5)
        case "fasting":
            left.move(to: CGPoint(x: 38.5, y: 74))
            left.addQuadCurve(to: CGPoint(x: 42, y: 85), control: CGPoint(x: 34, y: 81))
            right.move(to: CGPoint(x: 61.5, y: 74))
            right.addQuadCurve(to: CGPoint(x: 58, y: 85), control: CGPoint(x: 66, y: 81))
            handL = CGPoint(x: 43.5, y: 85.5)
            handR = CGPoint(x: 56.5, y: 85.5)
        default:
            left.move(to: CGPoint(x: 39, y: 74))
            left.addQuadCurve(to: CGPoint(x: 33.5, y: 85), control: CGPoint(x: 34, y: 79))
            right.move(to: CGPoint(x: 61, y: 74))
            right.addQuadCurve(to: CGPoint(x: 66.5, y: 85), control: CGPoint(x: 66, y: 79))
            handL = CGPoint(x: 33.4, y: 86.2)
            handR = CGPoint(x: 66.6, y: 86.2)
        }

        context.stroke(left, with: .color(gi), style: style)
        context.stroke(right, with: .color(gi), style: style)
        context.fill(circle(center: handL, radius: 4.2), with: .color(skin))
        context.fill(circle(center: handR, radius: 4.2), with: .color(skin))
    }

    // MARK: - Head

    private func drawHead(in context: inout GraphicsContext) {
        var head = context
        // Rotate around the head center (50, 40), then apply the slump shift.
        head.translateBy(x: 50, y: 40)
        head.rotate(by: headTilt)
        head.translateBy(x: -50, y: -40 + bodyShiftY * 0.4)

        head.fill(circle(center: CGPoint(x: 50, y: 40), radius: 27.5), with: .color(gi))

        var face = Path()
        face.move(to: CGPoint(x: 28.5, y: 40.5))
        face.addQuadCurve(to: CGPoint(x: 50, y: 26.5), control: CGPoint(x: 28.5, y: 26.5))
        face.addQuadCurve(to: CGPoint(x: 71.5, y: 40.5), control: CGPoint(x: 71.5, y: 26.5))
        face.addQuadCurve(to: CGPoint(x: 50, y: 54), control: CGPoint(x: 71.5, y: 54))
        face.addQuadCurve(to: CGPoint(x: 28.5, y: 40.5), control: CGPoint(x: 28.5, y: 54))
        face.closeSubpath()
        head.fill(face, with: .color(skin))

        var hoodEdge = Path()
        hoodEdge.move(to: CGPoint(x: 28.5, y: 40.5))
        hoodEdge.addQuadCurve(to: CGPoint(x: 50, y: 26.5), control: CGPoint(x: 28.5, y: 26.5))
        hoodEdge.addQuadCurve(to: CGPoint(x: 71.5, y: 40.5), control: CGPoint(x: 71.5, y: 26.5))
        head.stroke(hoodEdge, with: .color(giDark.opacity(0.5)), style: StrokeStyle(lineWidth: 1.6))

        var band = Path()
        band.move(to: CGPoint(x: 27, y: 27.5))
        band.addQuadCurve(to: CGPoint(x: 73, y: 27.5), control: CGPoint(x: 50, y: 20.5))
        band.addLine(to: CGPoint(x: 73, y: 33.5))
        band.addQuadCurve(to: CGPoint(x: 27, y: 33.5), control: CGPoint(x: 50, y: 27))
        band.closeSubpath()
        head.fill(band, with: .color(palette.accent))

        var bandShade = Path()
        bandShade.move(to: CGPoint(x: 27, y: 31.5))
        bandShade.addQuadCurve(to: CGPoint(x: 73, y: 31.5), control: CGPoint(x: 50, y: 25.2))
        bandShade.addLine(to: CGPoint(x: 73, y: 33.5))
        bandShade.addQuadCurve(to: CGPoint(x: 27, y: 33.5), control: CGPoint(x: 50, y: 27))
        bandShade.closeSubpath()
        head.fill(bandShade, with: .color(palette.accentDeep.opacity(0.55)))

        var tailBack = Path()
        tailBack.move(to: CGPoint(x: 71.5, y: 30))
        tailBack.addQuadCurve(to: CGPoint(x: 85, y: 30.5), control: CGPoint(x: 80, y: 26.5))
        tailBack.addQuadCurve(to: CGPoint(x: 74.5, y: 36.5), control: CGPoint(x: 79, y: 32.5))
        tailBack.closeSubpath()
        head.fill(tailBack, with: .color(palette.accentDeep))

        var tailFront = Path()
        tailFront.move(to: CGPoint(x: 71.5, y: 32))
        tailFront.addQuadCurve(to: CGPoint(x: 81, y: 40), control: CGPoint(x: 78, y: 34))
        tailFront.addQuadCurve(to: CGPoint(x: 71, y: 37.5), control: CGPoint(x: 74.5, y: 39))
        tailFront.closeSubpath()
        head.fill(tailFront, with: .color(palette.accent))

        drawFaceFeatures(in: &head)
    }

    private func drawFaceFeatures(in context: inout GraphicsContext) {
        if state == "disappointed" {
            // Sad brows: inner ends raised.
            var browL = Path()
            browL.move(to: CGPoint(x: eyeLeftX - 4, y: eyeY - 5.6))
            browL.addLine(to: CGPoint(x: eyeLeftX + 3.4, y: eyeY - 8))
            var browR = Path()
            browR.move(to: CGPoint(x: eyeRightX + 4, y: eyeY - 5.6))
            browR.addLine(to: CGPoint(x: eyeRightX - 3.4, y: eyeY - 8))
            let style = StrokeStyle(lineWidth: 2, lineCap: .round)
            context.stroke(browL, with: .color(ink), style: style)
            context.stroke(browR, with: .color(ink), style: style)
        }

        drawEye(at: eyeLeftX, in: &context)
        drawEye(at: eyeRightX, in: &context)

        context.fill(
            ellipse(center: CGPoint(x: 35, y: 46), rx: 3.4, ry: 2.0),
            with: .color(blush)
        )
        context.fill(
            ellipse(center: CGPoint(x: 65, y: 46), rx: 3.4, ry: 2.0),
            with: .color(blush)
        )

        drawMouth(in: &context)
    }

    private func drawEye(at cx: CGFloat, in context: inout GraphicsContext) {
        switch state {
        case "proud":
            var arc = Path()
            arc.move(to: CGPoint(x: cx - 4.4, y: eyeY + 1))
            arc.addQuadCurve(to: CGPoint(x: cx + 4.4, y: eyeY + 1), control: CGPoint(x: cx, y: eyeY - 5.4))
            context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        case "fasting":
            var arc = Path()
            arc.move(to: CGPoint(x: cx - 4.2, y: eyeY))
            arc.addQuadCurve(to: CGPoint(x: cx + 4.2, y: eyeY), control: CGPoint(x: cx, y: eyeY + 3.4))
            context.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        case "thirsty", "tired":
            // Heavy-lidded: iris, then a skin lid, then the lid line.
            context.fill(ellipse(center: CGPoint(x: cx, y: eyeY + 1), rx: 4.4, ry: 4.6), with: .color(ink))
            let lid = Path(roundedRect: CGRect(x: cx - 4.8, y: eyeY - 4.4, width: 9.6, height: 4.6), cornerRadius: 2.2)
            context.fill(lid, with: .color(skin))
            var lidLine = Path()
            lidLine.move(to: CGPoint(x: cx - 4.4, y: eyeY - 0.4))
            lidLine.addLine(to: CGPoint(x: cx + 4.4, y: eyeY - 0.4))
            context.stroke(lidLine, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        case "urgent":
            context.fill(circle(center: CGPoint(x: cx, y: eyeY), radius: 5.4), with: .color(.white))
            context.fill(circle(center: CGPoint(x: cx, y: eyeY), radius: 3.1), with: .color(ink))
            context.fill(circle(center: CGPoint(x: cx + 1, y: eyeY - 1.2), radius: 1.1), with: .color(.white))
        case "disappointed":
            context.fill(ellipse(center: CGPoint(x: cx, y: eyeY + 1.5), rx: 4.0, ry: 4.6), with: .color(ink))
            context.fill(circle(center: CGPoint(x: cx + 1.2, y: eyeY), radius: 1.3), with: .color(.white.opacity(0.85)))
        case "achievement":
            context.fill(star(center: CGPoint(x: cx, y: eyeY), outer: 5.6, inner: 2.0, rotation: -.pi / 2), with: .color(ink))
        default:
            context.fill(ellipse(center: CGPoint(x: cx, y: eyeY), rx: 4.6, ry: 5.6), with: .color(ink))
            context.fill(circle(center: CGPoint(x: cx + 1.4, y: eyeY - 1.8), radius: 1.6), with: .color(.white.opacity(0.9)))
        }
    }

    private func drawMouth(in context: inout GraphicsContext) {
        switch state {
        case "thirsty":
            context.fill(ellipse(center: CGPoint(x: 50, y: 48.4), rx: 2.6, ry: 3.0), with: .color(ink))
            context.fill(
                ellipse(center: CGPoint(x: 50, y: 49.6), rx: 1.5, ry: 1.4),
                with: .color(Color(red: 0xE4 / 255.0, green: 0x8A / 255.0, blue: 0x8A / 255.0))
            )
        case "urgent":
            context.fill(ellipse(center: CGPoint(x: 50, y: 48.6), rx: 2.8, ry: 3.4), with: .color(ink))
        case "tired":
            context.fill(ellipse(center: CGPoint(x: 50, y: 48.8), rx: 2.3, ry: 2.8), with: .color(ink))
        case "proud":
            var smile = Path()
            smile.move(to: CGPoint(x: 45.5, y: 46.5))
            smile.addQuadCurve(to: CGPoint(x: 54.5, y: 46.5), control: CGPoint(x: 50, y: 51.5))
            context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        case "achievement":
            var grin = Path()
            grin.move(to: CGPoint(x: 44.5, y: 46))
            grin.addQuadCurve(to: CGPoint(x: 55.5, y: 46), control: CGPoint(x: 50, y: 53))
            context.stroke(grin, with: .color(ink), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
        case "disappointed":
            var frown = Path()
            frown.move(to: CGPoint(x: 46.5, y: 50))
            frown.addQuadCurve(to: CGPoint(x: 53.5, y: 50), control: CGPoint(x: 50, y: 47.2))
            context.stroke(frown, with: .color(ink), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
        default:
            var smile = Path()
            smile.move(to: CGPoint(x: 47, y: 47.5))
            smile.addQuadCurve(to: CGPoint(x: 53, y: 47.5), control: CGPoint(x: 50, y: 49.5))
            context.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    // MARK: - Props

    private func drawAura(in context: inout GraphicsContext) {
        let ring = circle(center: CGPoint(x: 50, y: 44), radius: 41)
        context.stroke(
            ring,
            with: .color(palette.accent.opacity(0.35)),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [5, 7])
        )
    }

    private func drawSparks(in context: inout GraphicsContext) {
        context.fill(star(center: CGPoint(x: 15, y: 20), outer: 4.5, inner: 1.9, rotation: 0.3), with: .color(gold))
        context.fill(star(center: CGPoint(x: 85, y: 16), outer: 3.6, inner: 1.5, rotation: 0.9), with: .color(palette.accent))
        context.fill(star(center: CGPoint(x: 12, y: 52), outer: 3.0, inner: 1.3, rotation: 1.4), with: .color(gold))
        context.fill(star(center: CGPoint(x: 88, y: 48), outer: 4.2, inner: 1.8, rotation: 0.1), with: .color(gold))
    }

    private func drawDroplet(in context: inout GraphicsContext) {
        var drop = context
        drop.translateBy(x: 76, y: 30)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -7))
        path.addQuadCurve(to: CGPoint(x: 0, y: 6), control: CGPoint(x: 5.8, y: 1.5))
        path.addQuadCurve(to: CGPoint(x: 0, y: -7), control: CGPoint(x: -5.8, y: 1.5))
        path.closeSubpath()
        drop.fill(path, with: .color(droplet))
        drop.fill(circle(center: CGPoint(x: -1.6, y: 1.4), radius: 1.4), with: .color(.white.opacity(0.75)))
    }

    private func drawExclamation(in context: inout GraphicsContext) {
        var mark = context
        mark.translateBy(x: 18, y: 18)
        mark.rotate(by: .degrees(-10))
        let bar = Path(roundedRect: CGRect(x: -2.1, y: -9, width: 4.2, height: 11), cornerRadius: 2.1)
        mark.fill(bar, with: .color(palette.accent))
        mark.fill(circle(center: CGPoint(x: 0, y: 6.4), radius: 2.2), with: .color(palette.accent))
    }

    private func drawZzz(in context: inout GraphicsContext) {
        var big = Path()
        big.move(to: CGPoint(x: 76, y: 22))
        big.addLine(to: CGPoint(x: 83, y: 22))
        big.addLine(to: CGPoint(x: 76, y: 29))
        big.addLine(to: CGPoint(x: 83, y: 29))
        context.stroke(big, with: .color(mist), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        var small = Path()
        small.move(to: CGPoint(x: 85, y: 12))
        small.addLine(to: CGPoint(x: 90, y: 12))
        small.addLine(to: CGPoint(x: 85, y: 17))
        small.addLine(to: CGPoint(x: 90, y: 17))
        context.stroke(small, with: .color(mist), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    // MARK: - Shape helpers

    private func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func ellipse(center: CGPoint, rx: CGFloat, ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2))
    }

    /// Four-point sparkle star as an 8-vertex polygon.
    private func star(center: CGPoint, outer: CGFloat, inner: CGFloat, rotation: CGFloat) -> Path {
        var path = Path()
        for i in 0..<8 {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = rotation + CGFloat(i) * .pi / 4
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

#Preview("All states") {
    let states = ["neutral", "thirsty", "fasting", "urgent", "proud", "disappointed", "tired", "achievement"]
    return ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 16) {
            ForEach(states, id: \.self) { state in
                VStack(spacing: 4) {
                    MascotIllustration(stateName: state, palette: .ninjaMale)
                        .frame(width: 110, height: 110)
                    Text(state).font(.caption2)
                }
            }
            ForEach(states, id: \.self) { state in
                MascotIllustration(stateName: state, palette: .ninjaFemale)
                    .frame(width: 110, height: 110)
            }
        }
        .padding()
    }
}
