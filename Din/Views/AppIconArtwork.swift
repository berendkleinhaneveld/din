import SwiftUI

/// The app icon's artwork, drawn live rather than loaded from `Din.icns`.
///
/// Everything the mockup needed has a SwiftUI equivalent: CSS radial gradients become
/// `EllipticalGradient`, the crest highlights become stroked `WaveShape`s, and the frosted panes
/// become a blurred copy of the ground masked to each sheet — which is what a backdrop blur amounts
/// to when you are the one drawing the backdrop. The one gap is `feTurbulence`, so the scatter
/// texture is generated in `IconNoise` instead.
struct AppIconArtwork: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let palette = colorScheme == .dark ? IconPalette.dark : IconPalette.light

            ZStack {
                ground(palette)

                ForEach(Array(zip(IconGeometry.crests, palette.panes).enumerated()), id: \.offset) { index, pair in
                    let (wave, pane) = pair
                    let sheet = WaveShape(wave: wave, closed: true)
                    let crest = WaveShape(wave: wave, closed: false)
                    let fade = IconGeometry.specularFade(alternate: !index.isMultiple(of: 2))

                    crest
                        .stroke(pane.shadow, lineWidth: IconGeometry.width(0.034, minimum: 2.5, side: side))
                        .blur(radius: side * 0.016)

                    // The frost: the ground behind, blurred, showing only through this sheet. The
                    // blur reaches past the crest, which is what softens the edge convincingly.
                    ground(palette)
                        .blur(radius: side * palette.frost)
                        .mask(sheet)

                    Rectangle()
                        .fill(tint(pane, wave: wave))
                        .mask(sheet)

                    IconNoise.grain.map { noise in
                        Image(decorative: noise, scale: 1)
                            .resizable()
                            .blendMode(.overlay)
                            .opacity(0.34)
                            .mask(sheet)
                    }

                    crest
                        .stroke(pane.bloom, lineWidth: IconGeometry.width(0.024, minimum: 3, side: side))
                        .blur(radius: side * 0.009)
                        .mask(fade)

                    crest
                        .stroke(pane.specular, lineWidth: IconGeometry.width(0.0038, minimum: 1, side: side))
                        .mask(fade)
                }
            }
            .clipShape(IconGeometry.tileShape(side: side))
            .overlay(
                IconGeometry.tileShape(side: side)
                    .strokeBorder(palette.rim, lineWidth: IconGeometry.width(0.006, minimum: 1, side: side))
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Din")
    }

    private func ground(_ palette: IconPalette) -> some View {
        ZStack {
            Rectangle()
                .fill(LinearGradient(stops: palette.base, startPoint: .top, endPoint: .bottom))

            // Every layer fills the frame and the blob is placed by the gradient's own centre.
            // Framing and positioning children here instead left the ZStack's size ambiguous.
            ForEach(Array(palette.blobs.enumerated()), id: \.offset) { _, blob in
                Rectangle()
                    .fill(
                        EllipticalGradient(
                            colors: [blob.color, blob.color.opacity(0)],
                            center: blob.center,
                            startRadiusFraction: 0,
                            endRadiusFraction: blob.radius
                        )
                    )
                    .scaleEffect(x: 1, y: blob.aspect, anchor: blob.center)
            }

            // Coarse structure for the panes to scatter. Blurring a smooth gradient looks exactly
            // like not blurring it, so without this the frost has nothing to work on.
            IconNoise.coarse.map { noise in
                Image(decorative: noise, scale: 1)
                    .resizable()
                    .blendMode(.overlay)
                    .opacity(0.38)
            }
        }
    }

    /// Exponential falloff below the crest, anchored above the highest point the crest reaches so
    /// the knee in the ramp never shows as a horizontal seam.
    private func tint(_ pane: Pane, wave: Wave) -> LinearGradient {
        let start = wave.baseY - wave.reach
        var stops: [Gradient.Stop] = []
        for step in 0...6 {
            let t = CGFloat(step) / 6
            let alpha = pane.tintEnd + (pane.tintStart - pane.tintEnd) * exp(-3 * t)
            stops.append(Gradient.Stop(color: pane.tint.opacity(alpha), location: min(1, start + t * pane.fade)))
        }
        stops.append(Gradient.Stop(color: pane.tint.opacity(pane.tintEnd), location: 1))
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

/// A soft colour wash over the ground. `radius` is the fraction of the frame at which the wash
/// reaches full transparency — 0.5 would reach the edge — and `aspect` squashes it into the ellipse
/// the CSS original used.
struct Blob {
    let color: Color
    let center: UnitPoint
    let radius: CGFloat
    let aspect: CGFloat
}

/// One sheet of glass: how much it tints what shows through it, and how its edge is lit.
struct Pane {
    let tint: Color
    let tintStart: CGFloat
    let tintEnd: CGFloat
    let fade: CGFloat
    let specular: Color
    let bloom: Color
    let shadow: Color
}

struct IconPalette {
    let base: [Gradient.Stop]
    let blobs: [Blob]
    let panes: [Pane]
    let rim: LinearGradient
    let frost: CGFloat

    static let dark = IconPalette(
        base: [
            Gradient.Stop(color: Color(red: 0.204, green: 0.125, blue: 0.290), location: 0),
            Gradient.Stop(color: Color(red: 0.235, green: 0.141, blue: 0.329), location: 0.14),
            Gradient.Stop(color: Color(red: 0.110, green: 0.251, blue: 0.404), location: 0.44),
            Gradient.Stop(color: Color(red: 0.063, green: 0.376, blue: 0.494), location: 0.76),
            Gradient.Stop(color: Color(red: 0.047, green: 0.486, blue: 0.549), location: 1),
        ],
        blobs: [
            Blob(
                color: Color(red: 1.0, green: 0.659, blue: 0.408).opacity(0.58),
                center: UnitPoint(x: 0.70, y: 0.08),
                radius: 0.410, aspect: 0.688
            ),
            Blob(
                color: Color(red: 0.173, green: 0.651, blue: 0.855).opacity(0.55),
                center: UnitPoint(x: 0.14, y: 0.68),
                radius: 0.285, aspect: 0.653
            ),
            Blob(
                color: Color(red: 0.039, green: 0.839, blue: 0.800).opacity(0.42),
                center: UnitPoint(x: 0.88, y: 0.94),
                radius: 0.264, aspect: 0.636
            ),
        ],
        panes: [
            Pane(
                tint: Color(red: 0.588, green: 0.804, blue: 0.922), tintStart: 0.16, tintEnd: 0, fade: 0.30,
                specular: Color(red: 1.0, green: 0.871, blue: 0.745).opacity(0.88),
                bloom: Color(red: 1.0, green: 0.698, blue: 0.486).opacity(0.30),
                shadow: Color(red: 0.012, green: 0.024, blue: 0.055).opacity(0.60)
            ),
            Pane(
                tint: Color(red: 0.549, green: 0.808, blue: 0.941), tintStart: 0.19, tintEnd: 0, fade: 0.26,
                specular: Color(red: 0.847, green: 0.961, blue: 1.0).opacity(0.92),
                bloom: Color(red: 0.471, green: 0.824, blue: 1.0).opacity(0.32),
                shadow: Color(red: 0.012, green: 0.024, blue: 0.055).opacity(0.62)
            ),
            Pane(
                tint: Color(red: 0.518, green: 0.831, blue: 0.973), tintStart: 0.22, tintEnd: 0.02, fade: 0.22,
                specular: Color(red: 0.894, green: 0.980, blue: 1.0).opacity(0.98),
                bloom: Color(red: 0.510, green: 0.855, blue: 1.0).opacity(0.36),
                shadow: Color(red: 0.012, green: 0.024, blue: 0.055).opacity(0.64)
            ),
        ],
        rim: LinearGradient(
            stops: [
                Gradient.Stop(color: .white.opacity(0.42), location: 0),
                Gradient.Stop(color: .white.opacity(0.10), location: 0.45),
                Gradient.Stop(color: Color(red: 0.561, green: 0.831, blue: 0.941).opacity(0.16), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        ),
        frost: 0.045
    )

    static let light = IconPalette(
        base: [
            Gradient.Stop(color: Color(red: 1.0, green: 0.965, blue: 0.925), location: 0),
            Gradient.Stop(color: Color(red: 0.953, green: 0.886, blue: 0.839), location: 0.16),
            Gradient.Stop(color: Color(red: 0.761, green: 0.863, blue: 0.925), location: 0.42),
            Gradient.Stop(color: Color(red: 0.353, green: 0.655, blue: 0.831), location: 0.76),
            Gradient.Stop(color: Color(red: 0.165, green: 0.482, blue: 0.690), location: 1),
        ],
        blobs: [
            Blob(
                color: Color(red: 1.0, green: 0.804, blue: 0.596).opacity(0.70),
                center: UnitPoint(x: 0.72, y: 0.09),
                radius: 0.347, aspect: 0.608
            ),
            Blob(
                color: .white.opacity(0.55),
                center: UnitPoint(x: 0.16, y: 0.72),
                radius: 0.273, aspect: 0.637
            ),
            Blob(
                color: Color(red: 0.094, green: 0.431, blue: 0.659).opacity(0.45),
                center: UnitPoint(x: 0.86, y: 0.94),
                radius: 0.276, aspect: 0.652
            ),
        ],
        panes: [
            Pane(
                tint: .white, tintStart: 0.26, tintEnd: 0, fade: 0.30,
                specular: .white.opacity(0.95), bloom: .white.opacity(0.42),
                shadow: Color(red: 0.102, green: 0.259, blue: 0.392).opacity(0.24)
            ),
            Pane(
                tint: .white, tintStart: 0.28, tintEnd: 0, fade: 0.26,
                specular: .white.opacity(0.97), bloom: .white.opacity(0.46),
                shadow: Color(red: 0.102, green: 0.259, blue: 0.392).opacity(0.28)
            ),
            Pane(
                tint: .white, tintStart: 0.30, tintEnd: 0.03, fade: 0.22,
                specular: .white, bloom: .white.opacity(0.50),
                shadow: Color(red: 0.102, green: 0.259, blue: 0.392).opacity(0.32)
            ),
        ],
        rim: LinearGradient(
            stops: [
                Gradient.Stop(color: .white.opacity(0.95), location: 0),
                Gradient.Stop(color: .white.opacity(0.24), location: 0.45),
                Gradient.Stop(color: .white.opacity(0.35), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        ),
        frost: 0.045
    )
}

/// Value noise, summed over octaves. Stands in for SVG's `feTurbulence`, which SwiftUI has no
/// equivalent of: the coarse image gives the panes something to scatter, the fine one is the
/// scattering itself.
enum IconNoise {
    static let coarse = make(pixels: 256, lattice: 8, octaves: 4, seed: 3, contrast: 0.46)
    static let grain = make(pixels: 512, lattice: 256, octaves: 2, seed: 11, contrast: 0.30)

    private static func make(pixels: Int, lattice: Int, octaves: Int, seed: UInt64, contrast: Double) -> CGImage? {
        var state = seed &* 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            return Double(z >> 11) / Double(1 << 53)
        }

        var grids: [[Double]] = []
        var sizes: [Int] = []
        var size = lattice
        for _ in 0..<octaves {
            grids.append((0..<(size * size)).map { _ in next() })
            sizes.append(size)
            size *= 2
        }

        func sample(_ octave: Int, _ u: Double, _ v: Double) -> Double {
            let n = sizes[octave]
            let grid = grids[octave]
            let x = u * Double(n)
            let y = v * Double(n)
            let x0 = Int(x.rounded(.down))
            let y0 = Int(y.rounded(.down))
            let fx = x - Double(x0)
            let fy = y - Double(y0)
            let sx = fx * fx * (3 - 2 * fx)
            let sy = fy * fy * (3 - 2 * fy)
            let ix0 = ((x0 % n) + n) % n
            let iy0 = ((y0 % n) + n) % n
            let ix1 = (ix0 + 1) % n
            let iy1 = (iy0 + 1) % n
            let top = grid[iy0 * n + ix0] + (grid[iy0 * n + ix1] - grid[iy0 * n + ix0]) * sx
            let bottom = grid[iy1 * n + ix0] + (grid[iy1 * n + ix1] - grid[iy1 * n + ix0]) * sx
            return top + (bottom - top) * sy
        }

        var bytes = [UInt8](repeating: 0, count: pixels * pixels * 4)
        for py in 0..<pixels {
            for px in 0..<pixels {
                var value = 0.0
                var amplitude = 1.0
                var total = 0.0
                for octave in 0..<octaves {
                    value += sample(octave, Double(px) / Double(pixels), Double(py) / Double(pixels)) * amplitude
                    total += amplitude
                    amplitude *= 0.5
                }
                // Pulled toward mid grey, which is the no-op value for `overlay` blending.
                let grey = 0.5 + (value / total - 0.5) * contrast
                let byte = UInt8(max(0, min(255, grey * 255)))
                let offset = (py * pixels + px) * 4
                bytes[offset] = byte
                bytes[offset + 1] = byte
                bytes[offset + 2] = byte
                bytes[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: pixels * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

#if DEBUG
#Preview("App icon artwork") {
    HStack(spacing: 16) {
        AppIconArtwork().frame(width: 256, height: 256)
        AppIconArtwork().frame(width: 104, height: 104)
        AppIconArtwork().frame(width: 32, height: 32)
    }
    .padding(24)
}
#endif
