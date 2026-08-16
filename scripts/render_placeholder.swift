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

        for (name, scheme) in [("icon-light", ColorScheme.light), ("icon-dark", ColorScheme.dark)] {
            let icon = AppIconArtwork()
                .frame(width: 512, height: 512)
                .environment(\.colorScheme, scheme)
            write(icon, scale: 1, opaque: false, to: directory, named: name)
        }
        write(IconSheet(dark: false), scale: 2, opaque: true, to: directory, named: "icon-sheet-light")
        write(IconSheet(dark: true), scale: 2, opaque: true, to: directory, named: "icon-sheet-dark")

        // Both point sizes at the same pixel size, so the hairline floor — which binds hard at
        // 104 and barely at 256 — cannot be mistaken for a difference in the drawing itself.
        for (name, scheme) in [("tile-light", ColorScheme.light), ("tile-dark", ColorScheme.dark)] {
            for points in [CGFloat(256), CGFloat(104)] {
                let tile = ArtworkPlaceholder()
                    .frame(width: points, height: points)
                    .environment(\.colorScheme, scheme)
                write(tile, scale: 512 / points, opaque: false, to: directory, named: "\(name)-\(Int(points))")
            }
        }

        write(ListProbe(), scale: 2, opaque: true, to: directory, named: "probe-list")

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

/// The coloured icon at the sizes that matter, for judging how it survives scaling.
private struct IconSheet: View {
    let dark: Bool

    private let sizes: [CGFloat] = [256, 128, 64, 32, 16]

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            ForEach(sizes, id: \.self) { size in
                VStack(spacing: 8) {
                    AppIconArtwork().frame(width: size, height: size)
                    Text("\(Int(size))")
                        .font(.system(size: 9, design: .monospaced))
                        .opacity(0.45)
                }
            }
        }
        .padding(26)
        .frame(width: 620, alignment: .leading)
        .background(dark ? Color(red: 0.055, green: 0.063, blue: 0.078) : Color(red: 0.925, green: 0.929, blue: 0.937))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}


/// Does ImageRenderer draw a macOS `List`? On macOS a List is NSTableView-backed, and
/// ImageRenderer is documented to render SwiftUI only — if the rows come out blank, the README
/// screenshot cannot be produced this way and has to capture a real window instead.
private struct ListProbe: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("List probe — rows below should be visible")
                .font(.system(size: 10, design: .monospaced))
                .padding(6)
            Divider()
            List {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 8) {
                        Image(systemName: row == 0 ? "speaker.wave.2.fill" : "music.note")
                            .font(.system(size: 10))
                        Text("Track \(row + 1)").font(.system(size: 12))
                        Spacer()
                        Text("3:12").font(.system(size: 10, design: .monospaced)).opacity(0.5)
                    }
                    .frame(height: 26)
                }
            }
            .frame(height: 170)
        }
        .frame(width: 320)
        .background(Color(red: 0.925, green: 0.929, blue: 0.937))
    }
}
