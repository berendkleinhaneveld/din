import SwiftUI

/// Fallback artwork for tracks that carry no embedded image.
///
/// Drawn rather than shipped as a bitmap so it follows the appearance live. Every mark is
/// `Color.primary`, white or black at low alpha, never a fixed grey, so the tile takes its cast
/// from whatever the chrome resolves to instead of asserting a colour of its own.
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

                ForEach(Array(IconGeometry.crests.enumerated()), id: \.offset) { index, wave in
                    // The contact shadow is stroked along the crest before the sheet is filled, so
                    // the sheet covers its lower half and only the part above the crest reads.
                    WaveShape(wave: wave, closed: false)
                        .stroke(
                            Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10),
                            lineWidth: IconGeometry.width(0.034, minimum: 2.5, side: side)
                        )
                        .blur(radius: side * 0.016)

                    WaveShape(wave: wave, closed: true)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.038 : 0.032))

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
