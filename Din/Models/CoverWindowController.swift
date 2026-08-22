import AppKit
import SwiftUI

/// Resolving the app's single content window.
///
/// This lives here rather than on `AppDelegate` because `AppDelegate` is declared in
/// `DinApp.swift`, which the Assets workflow leaves out of its build — see that file's header.
/// Cover mode is triggered by a view, and a view that reached into `DinApp.swift` would keep
/// `swift build` and CI green while breaking the asset job with an error pointing at the renderer.
enum ContentWindow {
    /// Panels (popovers, the volume slider, save/open sheets) can become key but never main,
    /// so `canBecomeMain` keeps us on the real content window.
    static func find() -> NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
    }
}

/// One window, two shapes: the queue, and the current track's cover as a square.
///
/// A second window was the obvious alternative and is the wrong one. The window is already
/// `.hiddenTitleBar`, so there is no chrome to fight; and `AppDelegate.shouldHandleTransportKey`
/// gates on the event's window being the main one, so a second window would silently kill space,
/// `[` and `]` for as long as the cover had focus.
@MainActor
final class CoverWindowController: ObservableObject {
    static let shared = CoverWindowController()

    /// Whether the window is currently showing the cover rather than the queue.
    @Published private(set) var isCoverMode = false

    /// Below roughly this the hover overlay stops being a scrim over a cover and becomes the whole
    /// window: title, transport, waveform and times need about 130 pt between them.
    static let minSide: CGFloat = 220
    /// A judgement call rather than a derivation — past this the square stops being something you
    /// park in a corner.
    static let maxSide: CGFloat = 420

    /// The queue window's content size, stashed on the way into cover mode and handed back on the
    /// way out. Its *size*, not its frame: a square dragged to another corner of the screen should
    /// come back where you left it.
    private var queueSize: CGSize
    /// The square's own side, remembered across collapses once it has been set.
    private var coverSide: CGFloat?

    private enum Keys {
        static let coverMode = "din.coverMode"
        static let queueSize = "din.queueSize"
        static let coverSide = "din.coverSide"
    }

    private init() {
        let defaults = UserDefaults.standard
        queueSize =
            defaults.string(forKey: Keys.queueSize).map { NSSizeFromString($0) as CGSize }
            ?? CGSize(width: 320, height: 500)
        let side = defaults.double(forKey: Keys.coverSide)
        coverSide = side > 0 ? Self.clampSide(side) : nil
    }

    // MARK: - Entering and leaving

    func toggle() {
        if isCoverMode {
            exitCoverMode()
        } else {
            enterCoverMode()
        }
    }

    func enterCoverMode(animate: Bool = true) {
        guard !isCoverMode, let window = ContentWindow.find() else { return }
        enter(window, animate: animate, capturingQueueSize: true)
    }

    func exitCoverMode(animate: Bool = true) {
        guard isCoverMode, let window = ContentWindow.find() else { return }

        coverSide = contentSize(of: window).width
        isCoverMode = false
        saveState()

        // `aspectRatio` and `resizeIncrements` are mutually exclusive: setting either clears the
        // other, and there is no zero-ratio escape hatch for the first. The size limits need no
        // undoing — `ContentView`'s queue branch asks for its own the moment the mode flips.
        window.resizeIncrements = NSSize(width: 1, height: 1)
        window.isMovableByWindowBackground = false
        setStandardButtons(hidden: false, in: window)

        resize(window, toContent: queueSize, animate: animate)
    }

    /// Reapply the shape the app was last quit in, once there is a window to apply it to.
    ///
    /// The queue size has to come from what was persisted rather than from the window: macOS may
    /// have restored the window already square, and capturing that would lose the queue's size for
    /// good the first time the cover was closed.
    func restoreOnLaunch() {
        guard UserDefaults.standard.bool(forKey: Keys.coverMode) else { return }
        guard let window = ContentWindow.find() else { return }
        enter(window, animate: false, capturingQueueSize: false)
    }

    private func enter(_ window: NSWindow, animate: Bool, capturingQueueSize: Bool) {
        let content = contentSize(of: window)
        if capturingQueueSize {
            queueSize = content
        }
        // The first collapse takes its side from the queue window's own width — at the default
        // width that makes the collapse purely vertical. After that the square is its own thing.
        let side = coverSide ?? Self.clampSide(content.width)
        coverSide = side

        isCoverMode = true
        saveState()

        // Frame-based rather than `contentAspectRatio`. On a `fullSizeContentView` window the
        // content rect *is* the frame, but the `content…` variants still convert as though a
        // titlebar sat above it, which makes a square content rect a 28 pt-taller window.
        //
        // The 220–420 clamps are not set here on purpose. SwiftUI rewrites the window's own
        // `minSize` and `maxSize` from the hosted view on every layout pass, so anything set here
        // is overwritten a moment later; `ContentView` declares them instead. This ratio is the
        // piece SwiftUI has no opinion about, and it is what carries the width clamps over to the
        // height.
        window.aspectRatio = NSSize(width: 1, height: 1)
        // With no titlebar and no overlay at rest there is nothing else to grab.
        window.isMovableByWindowBackground = true
        setStandardButtons(hidden: true, in: window)

        resize(window, toContent: CGSize(width: side, height: side), animate: animate)
    }

    // MARK: - Window geometry

    /// Resize anchored to the window's top-left corner, the way macOS resizes anyway.
    ///
    /// Cocoa frames have a bottom-left origin, so holding the top edge still means moving the
    /// origin by the height the window gains or loses. Leaving the origin alone instead grows the
    /// window downward, off the bottom of the screen.
    private func resize(_ window: NSWindow, toContent size: CGSize, animate: Bool) {
        let target = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - target.height
        frame.size = target.size
        window.setFrame(frame, display: true, animate: animate)
    }

    private func contentSize(of window: NSWindow) -> CGSize {
        window.contentRect(forFrameRect: window.frame).size
    }

    private func setStandardButtons(hidden: Bool, in window: NSWindow) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    private static func clampSide(_ side: CGFloat) -> CGFloat {
        min(max(side, minSide), maxSide)
    }

    // MARK: - Persistence

    /// Note the existing defaults keys are lowercase `din.`, whatever AGENTS.md says.
    func saveState() {
        // While collapsed the square's live size is whatever it was last dragged to, which nothing
        // else has recorded yet.
        if isCoverMode, let window = ContentWindow.find() {
            coverSide = Self.clampSide(contentSize(of: window).width)
        }

        let defaults = UserDefaults.standard
        defaults.set(isCoverMode, forKey: Keys.coverMode)
        defaults.set(NSStringFromSize(queueSize), forKey: Keys.queueSize)
        if let coverSide {
            defaults.set(Double(coverSide), forKey: Keys.coverSide)
        }
    }
}
