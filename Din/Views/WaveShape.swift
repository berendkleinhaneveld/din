import SwiftUI

/// One crest of the icon: a sine rocked off horizontal by `tilt`, in unit coordinates.
struct Wave {
    let baseY: CGFloat
    let amplitude: CGFloat
    let cycles: CGFloat
    let phase: CGFloat
    let tilt: CGFloat

    func y(atX x: CGFloat) -> CGFloat {
        baseY + tilt * (x - 0.5) + amplitude * sin(cycles * 2 * .pi * x + phase * 2 * .pi)
    }

    /// How far above `baseY` the crest actually reaches. A tilted crest rises higher than its
    /// amplitude alone, which matters when a gradient has to start above every point of it.
    var reach: CGFloat {
        amplitude + abs(tilt) / 2
    }
}

/// The crest as an open line to stroke, or closed to one edge as a region to fill or mask with.
struct WaveShape: Shape {
    /// Which edge a closed shape runs to: the sheet below a crest closes down, the crevice
    /// above it closes up.
    enum Closure {
        case bottom
        case top
    }

    let wave: Wave
    let closed: Bool
    var closing: Closure = .bottom

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
            let edge = closing == .bottom ? rect.maxY : rect.minY
            path.addLine(to: CGPoint(x: rect.maxX, y: edge))
            path.addLine(to: CGPoint(x: rect.minX, y: edge))
            path.closeSubpath()
        }
        return path
    }
}

enum IconGeometry {
    /// The three crests of the icon, normalised to the unit square.
    static let crests: [Wave] = [
        Wave(baseY: 0.432, amplitude: 0.078, cycles: 0.80, phase: 0.10, tilt: -0.122),
        Wave(baseY: 0.632, amplitude: 0.088, cycles: 1.05, phase: 0.62, tilt: -0.122),
        Wave(baseY: 0.832, amplitude: 0.066, cycles: 0.88, phase: 0.34, tilt: -0.122),
    ]

    /// How far below each crest its lit face fades out, as a fraction of the frame. The lower
    /// crests get less room because they sit closer together; the icon's panes use the same three
    /// values for their tints.
    static let sheetFades: [CGFloat] = [0.30, 0.26, 0.22]

    /// Ratio Apple uses for the icon superellipse, as a continuous rounded rectangle.
    static func tileShape(side: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
    }

    /// Line weights are a fraction of the icon, which leaves a 0.1pt highlight at list-row sizes.
    /// Holding them to a minimum in points keeps the detail visible in the small cases without
    /// touching the large ones, the way a hand-tuned icon set does.
    static func width(_ fraction: CGFloat, minimum: CGFloat, side: CGFloat) -> CGFloat {
        max(side * fraction, minimum)
    }

    /// A lit edge is never evenly bright. Fading the highlight along its length keeps the crest
    /// reading as light catching a surface rather than as a drawn line.
    static func specularFade(alternate: Bool) -> LinearGradient {
        let stops: [Double] = alternate ? [0.22, 0.85, 0.55, 0.95, 0.35] : [0.30, 0.55, 1.00, 0.62, 0.22]
        return LinearGradient(
            colors: stops.map { Color.white.opacity($0) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
