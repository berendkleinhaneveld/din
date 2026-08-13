import SwiftUI
import UniformTypeIdentifiers

@main
struct DinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var recentItems = RecentItems.shared

    var body: some Scene {
        WindowGroup {
            ContentView(manager: .shared)
        }
        .handlesExternalEvents(matching: [])
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 320, height: 500)
        .commands {
            // Disable tabs
            CommandGroup(replacing: .toolbar) {}

            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    Self.showOpenPanel(replace: true)
                }
                .keyboardShortcut("o")

                Button("Add to Playlist...") {
                    Self.showOpenPanel(replace: false)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Save Playlist...") {
                    PlaylistManager.shared.savePlaylistToFile()
                }
                .keyboardShortcut("s")

                Button("Load Playlist...") {
                    PlaylistManager.shared.loadPlaylistFromFile(replace: true)
                }
                .keyboardShortcut("l")

                Divider()

                Menu("Open Recent") {
                    ForEach(recentItems.recentFiles, id: \.self) { path in
                        Button(RecentItems.displayName(for: path)) {
                            Self.openRecentFile(path: path)
                        }
                    }
                    if !recentItems.recentFiles.isEmpty && !recentItems.recentPlaylists.isEmpty {
                        Divider()
                    }
                    ForEach(recentItems.recentPlaylists, id: \.self) { path in
                        Button(RecentItems.displayName(for: path)) {
                            Self.openRecentPlaylist(path: path)
                        }
                    }
                    if !recentItems.recentFiles.isEmpty || !recentItems.recentPlaylists.isEmpty {
                        Divider()
                    }
                    Button("Clear Menu") {
                        RecentItems.shared.clearAll()
                    }
                }
            }

            // Recovery path: the File menu's "New Window" item is replaced above,
            // so without this there is no menu command that can bring the window
            // back once it has been closed.
            CommandGroup(after: .windowList) {
                Button("Din Window") {
                    (NSApp.delegate as? AppDelegate)?.showMainWindow()
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            CommandMenu("Playback") {
                Button("Volume Up") {
                    let mgr = PlaylistManager.shared
                    mgr.setVolume(min(1, mgr.volume + 0.1))
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Volume Down") {
                    let mgr = PlaylistManager.shared
                    mgr.setVolume(max(0, mgr.volume - 0.1))
                }
                .keyboardShortcut("-", modifiers: .command)
            }
        }
    }

    static func showOpenPanel(replace: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            RecentItems.shared.addFile(url)
        }
        if replace {
            PlaylistManager.shared.replacePlaylist(urls: panel.urls)
        } else {
            PlaylistManager.shared.addTracks(urls: panel.urls)
        }
    }

    static func openRecentFile(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            let alert = NSAlert()
            alert.messageText = "File Not Found"
            alert.informativeText = "The item at \"\(RecentItems.displayName(for: path))\" can't be found."
            alert.alertStyle = .warning
            alert.runModal()
            RecentItems.shared.remove(path)
            return
        }
        let url = URL(fileURLWithPath: path)
        PlaylistManager.shared.replacePlaylist(urls: [url])
    }

    static func openRecentPlaylist(path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            let alert = NSAlert()
            alert.messageText = "File Not Found"
            alert.informativeText = "The item at \"\(RecentItems.displayName(for: path))\" can't be found."
            alert.alertStyle = .warning
            alert.runModal()
            RecentItems.shared.remove(path)
            return
        }
        let url = URL(fileURLWithPath: path)
        PlaylistManager.shared.loadPlaylistFromURL(url, replace: true)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Strong reference to the content window, paired with `isReleasedWhenClosed = false`
    /// so closing it doesn't destroy it and it can be shown again later.
    private var cachedWindow: NSWindow?

    /// The app's content window, resolved lazily.
    ///
    /// This deliberately does *not* rely on a single lookup at launch. The SwiftUI
    /// `WindowGroup` window may not exist yet one runloop turn after
    /// `applicationDidFinishLaunching` — e.g. a background launch, a launch to
    /// service an open-file event, or a launch where AppKit is still restoring
    /// saved window state. A one-shot capture leaves the reference `nil` forever
    /// in those cases, and then closing the window strands the app with no way back.
    var mainWindow: NSWindow? {
        if let cachedWindow { return cachedWindow }
        guard let window = Self.findContentWindow() else { return nil }
        window.isReleasedWhenClosed = false
        cachedWindow = window
        return window
    }

    private static func findContentWindow() -> NSWindow? {
        // Panels (popovers, the volume slider, save/open sheets) can become key
        // but never main, so `canBecomeMain` keeps us on the real content window.
        NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
    }

    /// Bring the content window back, whatever state it was left in.
    func showMainWindow() {
        guard let window = mainWindow else { return }
        // `makeKeyAndOrderFront` does not un-minimize a window sitting in the Dock.
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Opening files while the window is closed should bring the app back,
        // not just start playing invisibly.
        showMainWindow()
        Task { @MainActor in
            for url in urls {
                RecentItems.shared.addFile(url)
            }
            PlaylistManager.shared.replacePlaylist(urls: urls)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            PlaylistManager.shared.saveState()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Returning false means "handled, don't do the default". Only claim that
        // when we actually have a window to show — otherwise returning false with
        // nothing to restore is what leaves the app running with no window and no
        // way to get one back (the File menu has no "New Window" item either).
        guard !flag else { return true }
        guard mainWindow != nil else { return true }
        showMainWindow()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable window tabbing (removes "Show Tab Bar" / "Show All Tabs" from View menu)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Pin the content window the first time it appears, however late that is.
        // A launch-time lookup alone can miss it entirely (see `mainWindow`), and a
        // window that was never pinned is gone for good once the user closes it.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, self.cachedWindow == nil else { return }
            guard let window = notification.object as? NSWindow, !(window is NSPanel) else { return }
            window.isReleasedWhenClosed = false
            self.cachedWindow = window
        }

        DispatchQueue.main.async {
            // Close extra content windows that SwiftUI may have created. `NSApp.windows`
            // has no defined order (it is not front-to-back), so this must key off the
            // window we identified rather than dropping the first element of the array —
            // otherwise it can close the real window and keep a stray one.
            guard let main = self.mainWindow else { return }
            for window in NSApp.windows where window !== main && window.isVisible && window.canBecomeMain {
                window.close()
            }
        }

        // Double-click on playlist row → play selected track
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if event.clickCount == 2 {
                // Walk up from hit view to confirm it's a table row
                if let contentView = event.window?.contentView,
                    let hitView = contentView.hitTest(event.locationInWindow)
                {
                    var view: NSView? = hitView
                    while let v = view {
                        if v is NSTableRowView {
                            Task { @MainActor in
                                let mgr = PlaylistManager.shared
                                if let selectedID = mgr.selection.first,
                                    let index = mgr.tracks.firstIndex(where: { $0.id == selectedID })
                                {
                                    mgr.playTrack(at: index)
                                }
                            }
                            break
                        }
                        view = v.superview
                    }
                }
            }
            return event
        }

        // Keyboard shortcuts
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.shouldHandleTransportKey(event) else { return event }

            switch event.charactersIgnoringModifiers {
            case " ":
                Task { @MainActor in PlaylistManager.shared.togglePlayPause() }
                return nil
            case "[":
                Task { @MainActor in PlaylistManager.shared.previous() }
                return nil
            case "]":
                Task { @MainActor in PlaylistManager.shared.next() }
                return nil
            case "{":
                Task { @MainActor in PlaylistManager.shared.skipBackward() }
                return nil
            case "}":
                Task { @MainActor in PlaylistManager.shared.skipForward() }
                return nil
            case "\r":
                Task { @MainActor in
                    let mgr = PlaylistManager.shared
                    if let selectedID = mgr.selection.first,
                        let index = mgr.tracks.firstIndex(where: { $0.id == selectedID })
                    {
                        mgr.playTrack(at: index)
                    }
                }
                return nil
            default:
                break
            }

            return event
        }

    }

    /// Whether a bare key press should be consumed as a transport shortcut.
    ///
    /// Local event monitors also fire while a modal panel is up, so without this
    /// check the Open/Save panels are unusable: space, `[`, `]`, `{` and `}` never
    /// reach the file-name field (they toggle playback and skip tracks instead)
    /// and Return is swallowed rather than confirming the panel. Events carrying
    /// a command/control/option modifier are also passed through so real menu
    /// shortcuts such as ⌘[ aren't shadowed.
    private func shouldHandleTransportKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control, .option, .function]) else { return false }
        guard let window = event.window, window === mainWindow else { return false }
        // Field editors are NSText subclasses; never steal keys from one.
        if window.firstResponder is NSText {
            return false
        }
        return true
    }
}
