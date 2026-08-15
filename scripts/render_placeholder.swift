import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders `ArtworkPlaceholder` to PNG on a macOS runner, so the view can be reviewed without a
/// Mac to hand. Compiled directly by `.github/workflows/render-placeholder.yml` alongside the view
/// itself — it is not part of the app target.
@main
struct RenderPlaceholder {
    @MainActor
    static func main() {
        // ImageRenderer wants an app to exist, even though nothing is shown.
        NSApplication.shared.setActivationPolicy(.accessory)

        let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        write(ContactSheet(dark: false), scale: 2, opaque: true, to: directory, named: "sheet-light")
        write(ContactSheet(dark: true), scale: 2, opaque: true, to: directory, named: "sheet-dark")

        for (name, scheme) in [("tile-light", ColorScheme.light), ("tile-dark", ColorScheme.dark)] {
            let tile = ArtworkPlaceholder()
                .frame(width: 256, height: 256)
                .environment(\.colorScheme, scheme)
            write(tile, scale: 2, opaque: false, to: directory, named: name)
        }

        print("rendered to \(directory.path)")
    }

    @MainActor
    private static func write<V: View>(_ view: V, scale: CGFloat, opaque: Bool, to directory: URL, named name: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = opaque
        guard let image = renderer.cgImage else {
            print("error: could not render \(name)")
            exit(1)
        }
        let url = directory.appendingPathComponent("\(name).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
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

/// The placeholder at the sizes it would actually appear, plus a strip over the real material so
/// the vibrancy question gets answered rather than guessed at.
private struct ContactSheet: View {
    let dark: Bool

    private let sizes: [CGFloat] = [256, 104, 64, 26]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(dark ? "DARK" : "LIGHT")
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.6)
                .opacity(0.4)

            HStack(alignment: .bottom, spacing: 22) {
                ForEach(sizes, id: \.self) { size in
                    VStack(spacing: 8) {
                        ArtworkPlaceholder().frame(width: size, height: size)
                        Text("\(Int(size))")
                            .font(.system(size: 9, design: .monospaced))
                            .opacity(0.45)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("over .ultraThinMaterial")
                    .font(.system(size: 9, design: .monospaced))
                    .opacity(0.45)
                HStack(alignment: .bottom, spacing: 22) {
                    ForEach(sizes, id: \.self) { size in
                        ArtworkPlaceholder().frame(width: size, height: size)
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(26)
        .frame(width: 640, alignment: .leading)
        .background(dark ? Color(red: 0.169, green: 0.176, blue: 0.192) : Color(red: 0.925, green: 0.929, blue: 0.937))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}
