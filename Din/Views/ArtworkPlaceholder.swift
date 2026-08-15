import SwiftUI

/// Fallback artwork for tracks that carry no embedded image.
///
/// Drawn rather than shipped as a bitmap so it follows the appearance live. Every mark is
/// `Color.primary`, white or black at low alpha, never a fixed grey: `ContentView` backs the window
/// with `.ultraThinMaterial`, so the chrome's resolved colour depends on the desktop behind the
/// window, and a baked-in tile would stop matching it as soon as the wallpaper changed.
///
/// The tile itself is a shallow well — darker than the chrome in light mode, lighter in dark. That
/// well is what gives the crest highlight somewhere to sit; on a bare light chrome a white line has
/// almost no range left to register in.
struct ArtworkPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Color.primary.opacity(colorScheme == .dark ? 0.070 : 0.055)

                ForEach(Array(Self.waves.enumerated()), id: \.offset) { index, wave in
                    // The contact shadow is stroked along the crest before the sheet is filled, so
                    // the sheet covers its lower half and only the part above the crest reads.
                    WaveShape(wave: wave, closed: false)
                        .stroke(
                            Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10),
                            lineWidth: Self.width(0.034, minimum: 2.5, side: side)
                        )
                        .blur(radius: side * 0.016)

                    WaveShape(wave: wave, closed: true)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.038 : 0.032))

                    WaveShape(wave: wave, closed: false)
                        .stroke(
                            Color.white.opacity(colorScheme == .dark ? 0.42 : 0.85),
                            lineWidth: Self.width(0.0038, minimum: 1, side: side)
                        )
                        .mask(Self.specularFade(alternate: !index.isMultiple(of: 2)))
                }
            }
            .clipShape(Self.tileShape(side: side))
            .overlay(
                Self.tileShape(side: side)
                    .strokeBorder(
                        Color.primary.opacity(0.13),
                        lineWidth: Self.width(0.006, minimum: 1, side: side)
                    )
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("No artwork")
    }

    /// Ratio Apple uses for the icon superellipse, as a continuous rounded rectangle.
    private static func tileShape(side: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
    }

    /// Line weights are a fraction of the icon, which leaves a 0.1pt highlight at list-row sizes.
    /// Holding them to a minimum in points keeps the detail visible in the small cases without
    /// touching the large ones, the way a hand-tuned icon set does.
    private static func width(_ fraction: CGFloat, minimum: CGFloat, side: CGFloat) -> CGFloat {
        max(side * fraction, minimum)
    }

    /// A lit edge is never evenly bright. Fading the highlight along its length keeps the crest
    /// reading as light catching a surface rather than as a drawn line.
    private static func specularFade(alternate: Bool) -> LinearGradient {
        let stops: [Double] = alternate ? [0.22, 0.85, 0.55, 0.95, 0.35] : [0.30, 0.55, 1.00, 0.62, 0.22]
        return LinearGradient(
            colors: stops.map { Color.white.opacity($0) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// The three crests of the "Fetch" icon direction, normalised to the unit square.
    private static let waves: [Wave] = [
        Wave(baseY: 0.432, amplitude: 0.078, cycles: 0.80, phase: 0.10, tilt: -0.122),
        Wave(baseY: 0.632, amplitude: 0.088, cycles: 1.05, phase: 0.62, tilt: -0.122),
        Wave(baseY: 0.832, amplitude: 0.066, cycles: 0.88, phase: 0.34, tilt: -0.122),
    ]
}

/// One crest: a sine rocked off horizontal by `tilt`, in unit coordinates.
private struct Wave {
    let baseY: CGFloat
    let amplitude: CGFloat
    let cycles: CGFloat
    let phase: CGFloat
    let tilt: CGFloat

    func y(atX x: CGFloat) -> CGFloat {
        baseY + tilt * (x - 0.5) + amplitude * sin(cycles * 2 * .pi * x + phase * 2 * .pi)
    }
}

/// The crest as an open line to stroke, or closed down to the bottom edge as a sheet to fill.
private struct WaveShape: Shape {
    let wave: Wave
    let closed: Bool

    private static let steps = 120

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 0...Self.steps {
            let t = CGFloat(step) / CGFloat(Self.steps)
            let point = CGPoint(x: rect.minX + t * rect.width, y: rect.minY + wave.y(atX: t) * rect.height)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

#Preview("Artwork placeholder") {
    HStack(spacing: 16) {
        ArtworkPlaceholder().frame(width: 104, height: 104)
        ArtworkPlaceholder().frame(width: 64, height: 64)
        ArtworkPlaceholder().frame(width: 26, height: 26)
    }
    .padding(24)
    .background(.ultraThinMaterial)
}
