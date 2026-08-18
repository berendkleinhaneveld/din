import SwiftUI

/// Fallback artwork for tracks that carry no embedded image.
///
/// Drawn rather than shipped as a bitmap so it follows the appearance live. The ground and the rim
/// are `Color.primary` at low alpha, never a fixed grey, so the tile takes its cast from whatever
/// the chrome resolves to instead of asserting a colour of its own. What the light does is fixed:
/// highlights are white and occlusion is black in both appearances, because a lit edge that
/// inverted with the appearance would move the light source with it.
///
/// The tile itself is a shallow well — darker than the chrome in light mode, lighter in dark. That
/// well is what gives the crest highlight somewhere to sit; on a bare light chrome a white line has
/// almost no range left to register in.
///
/// The light comes from above, and the whole tile is built to say so: each crest is occluded in the
/// crevice above it, lit along the line itself, and falls away beneath.
struct ArtworkPlaceholder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Color.primary.opacity(colorScheme == .dark ? 0.070 : 0.055)

                ForEach(Array(IconGeometry.crests.enumerated()), id: \.offset) { index, wave in
                    // Contact occlusion in the crevice where this sheet meets the one behind it.
                    // Masked to the near side of the crest: a blur centred on the line would spill
                    // downward and dim the lit face at exactly the point it should be brightest,
                    // which is the tell that flips the whole tile bottom-lit.
                    WaveShape(wave: wave, closed: false)
                        .stroke(
                            Color.black.opacity(colorScheme == .dark ? 0.20 : 0.075),
                            lineWidth: IconGeometry.width(0.034, minimum: 2.5, side: side)
                        )
                        .blur(radius: side * 0.016)
                        .mask(WaveShape(wave: wave, closed: true, closing: .top))

                    WaveShape(wave: wave, closed: true)
                        .fill(litFace(wave, fade: IconGeometry.sheetFades[index]))

                    WaveShape(wave: wave, closed: false)
                        .stroke(
                            Color.white.opacity(colorScheme == .dark ? 0.42 : 0.85),
                            lineWidth: IconGeometry.width(0.0038, minimum: 1, side: side)
                        )
                        .mask(IconGeometry.specularFade(alternate: !index.isMultiple(of: 2)))
                }
            }
            .clipShape(IconGeometry.tileShape(side: side))
            .overlay(
                IconGeometry.tileShape(side: side)
                    .strokeBorder(
                        Color.primary.opacity(0.13),
                        lineWidth: IconGeometry.width(0.006, minimum: 1, side: side)
                    )
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("No artwork")
    }

    /// The face below a crest, lit strongest at the edge that catches the light and gone within
    /// `fade` of it.
    ///
    /// A flat fill cannot put the light overhead. Every sheet closes to the bottom edge, so three
    /// flat sheets leave the foot of the tile carrying all three and the head carrying none — a
    /// tile that brightens the further down you look, which the eye reads as lit from below however
    /// the crests themselves are drawn. Decaying each sheet back to nothing keeps the lift attached
    /// to the edge it belongs to, the way the icon's panes do it with their tints.
    ///
    /// White in both appearances rather than `Color.primary`: this one is a highlight, and in the
    /// light appearance a black wash below the crest would light the tile from underneath again.
    private func litFace(_ wave: Wave, fade: CGFloat) -> LinearGradient {
        let start = wave.baseY - wave.reach
        let peak: CGFloat = colorScheme == .dark ? 0.09 : 0.17
        var stops = (0...6).map { step -> Gradient.Stop in
            let t = CGFloat(step) / 6
            return Gradient.Stop(
                color: Color.white.opacity(peak * exp(-3 * t)),
                location: min(1, start + t * fade)
            )
        }
        stops.append(Gradient.Stop(color: Color.white.opacity(0), location: 1))
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

#if DEBUG
    #Preview("Artwork placeholder") {
        HStack(spacing: 16) {
            ArtworkPlaceholder().frame(width: 104, height: 104)
            ArtworkPlaceholder().frame(width: 64, height: 64)
            ArtworkPlaceholder().frame(width: 26, height: 26)
        }
        .padding(24)
    }
#endif
