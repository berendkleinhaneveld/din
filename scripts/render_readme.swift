import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Regenerates the two committed images: the README screenshot and the 1024px icon that
/// `generate_assets.sh` turns into `Din.icns`.
///
/// The screenshot cannot be produced with `ImageRenderer`: the playlist is a SwiftUI `List`, which
/// is NSTableView-backed on macOS, and `ImageRenderer` draws a "not supported" placeholder in its
/// place. So the real interface is hosted in an `NSWindow` and its display is cached into a bitmap
/// — that renders AppKit properly and never touches the screen, so no screen-recording permission
/// is involved. Composing the two windows and the icon afterwards is plain SwiftUI, which
/// `ImageRenderer` handles fine.
///
/// Compiled by `.github/workflows/assets.yml` against the app's sources minus `DinApp.swift`,
/// whose `@main` would collide with this one. Nothing here ships in the app.
@main
struct RenderReadme {
    /// 2x, so the README image is crisp on the displays most people read it on. CI runners have no
    /// retina display, so this cannot come from the window's backing scale — it has to be drawn
    /// into an oversized bitmap by hand.
    static let scale: CGFloat = 2

    static let windowSize = CGSize(width: 335, height: 476)

    @MainActor
    static func main() {
        // .regular rather than .accessory: the traffic lights only take their colour when the
        // window can become key, and an accessory app's windows never do.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

        guard let light = captureApp(appearance: .aqua), let dark = captureApp(appearance: .darkAqua) else {
            print("error: could not capture the interface")
            exit(1)
        }

        let shot = ReadmeShot(light: light, dark: dark)
        writeImage(shot, size: ReadmeShot.canvas, to: root.appendingPathComponent("meta/Screenshot.png"))

        // 824 in a 1024 canvas is the macOS convention the old Pillow script also followed, and
        // what generate_assets.sh expects to slice up.
        let icon = ZStack {
            Color.clear
            AppIconArtwork().frame(width: 824, height: 824)
        }
        .frame(width: 1024, height: 1024)
        .environment(\.colorScheme, .dark)
        let build = root.appendingPathComponent("scripts/build")
        try? FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        writeImage(icon, size: CGSize(width: 1024, height: 1024), scale: 1,
                   to: build.appendingPathComponent("icon_1024.png"))
    }

    // MARK: - Capturing the real interface

    @MainActor
    private static func captureApp(appearance name: NSAppearance.Name) -> WindowShot? {
        let manager = PlaylistManager()
        manager.poseForScreenshot(tracks: Fixtures.tracks, playing: 0, at: 107, peaks: Fixtures.peaks)

        let host = NSHostingView(rootView: ContentView(manager: manager))
        host.frame = NSRect(origin: .zero, size: windowSize)

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: name)
        window.contentView = host
        window.setContentSize(windowSize)
        window.makeKeyAndOrderFront(nil)

        // Let layout, the waveform's TimelineView and metadata settle before the shutter.
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))

        // The content view's superview is the window's frame view, which carries the title bar and
        // the traffic lights.
        guard let frame = window.contentView?.superview, let image = snapshot(frame) else { return nil }

        // The window never becomes key on a CI runner — there is no foreground session — so macOS
        // draws the traffic lights inactive grey. Asking AppKit for the buttons' own frames and
        // painting the standard colours over them is exact, where guessing at offsets would not be.
        let lights = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
            .map { button -> CGRect in
                let rect = button.convert(button.bounds, to: frame)
                // AppKit measures from the bottom left; the composition measures from the top left.
                return CGRect(x: rect.minX, y: frame.bounds.height - rect.maxY, width: rect.width, height: rect.height)
            }

        window.orderOut(nil)
        return WindowShot(image: image, lights: lights)
    }

    /// Draws a view into a bitmap that is `scale` times its point size.
    ///
    /// `bitmapImageRepForCachingDisplay` would follow the display's backing scale, which is 1x on a
    /// CI runner. Building the rep by hand and telling it its own point size makes the context 2x
    /// regardless of what hardware is attached.
    @MainActor
    private static func snapshot(_ view: NSView) -> NSImage? {
        let bounds = view.bounds
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * scale),
                pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else { return nil }
        rep.size = bounds.size

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.displayIgnoringOpacity(bounds, in: context)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Writing

    @MainActor
    private static func writeImage<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        renderer.isOpaque = false
        guard let image = renderer.cgImage else {
            print("error: could not render \(url.lastPathComponent)")
            exit(1)
        }
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            print("error: could not open \(url.path)")
            exit(1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            print("error: could not write \(url.path)")
            exit(1)
        }
        print("wrote \(url.lastPathComponent) — \(image.width)x\(image.height)")
    }
}

// MARK: - Composition

/// A captured window, plus where its traffic lights sit so they can be recoloured.
private struct WindowShot {
    let image: NSImage
    let lights: [CGRect]
}

/// The two windows overlapping with the icon tucked in at the lower left, on transparency.
private struct ReadmeShot: View {
    let light: WindowShot
    let dark: WindowShot

    static let canvas = CGSize(width: 672, height: 600)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            window(light)
                .offset(x: 52, y: 30)

            AppIconArtwork()
                .frame(width: 208, height: 208)
                .shadow(color: .black.opacity(0.34), radius: 18, y: 10)
                .environment(\.colorScheme, .dark)
                .offset(x: 22, y: 372)

            window(dark)
                .offset(x: 282, y: 70)
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
    }

    private static let trafficLights: [Color] = [
        Color(red: 1.00, green: 0.373, blue: 0.341),
        Color(red: 0.996, green: 0.737, blue: 0.180),
        Color(red: 0.157, green: 0.784, blue: 0.251),
    ]

    private func window(_ shot: WindowShot) -> some View {
        Image(nsImage: shot.image)
            .resizable()
            .frame(width: shot.image.size.width, height: shot.image.size.height)
            .overlay(alignment: .topLeading) {
                ForEach(Array(shot.lights.enumerated()), id: \.offset) { index, rect in
                    Circle()
                        .fill(Self.trafficLights[index % Self.trafficLights.count])
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.30), radius: 16, y: 8)
    }
}

// MARK: - Fixtures

/// Fixed content, so the screenshot only changes when the interface does.
private enum Fixtures {
    static let tracks: [Track] = [
        track("La fleur gravité", 281),
        track("La voix de l'empereur", 296),
        track("R.Daneel", 293),
        track("Chachaaïm", 227),
        track("Requiem pour Chachaaïm", 121),
        track("The shining flower", 171),
        track("Le jardin des heures", 312),
        track("Nuit blanche", 303),
        track("Retour à la fille verte", 317),
    ]

    private static func track(_ title: String, _ duration: TimeInterval) -> Track {
        Track(
            url: URL(fileURLWithPath: "/fixtures/\(title).flac"),
            title: title,
            artist: "Syl Kougaï",
            album: "La fille verte",
            duration: duration
        )
    }

    /// A plausible waveform, generated rather than sampled so it never shifts between runs.
    static let peaks: [Float] = {
        var state: UInt64 = 20_240_617
        func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }
        return (0..<220).map { index in
            let position = Float(index) / 220
            // Loud through the middle, quieter at the head and tail, the way a track tends to be.
            let envelope = 0.32 + 0.68 * sin(Float.pi * position)
            return min(1, envelope * (0.45 + 0.55 * next()))
        }
    }()
}
