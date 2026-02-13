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
    private var mainWindow: NSWindow?

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                RecentItems.shared.addFile(url)
            }
            PlaylistManager.shared.replacePlaylist(urls: urls)
            NSApp.activate(ignoringOtherApps: true)
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
        if !flag {
            mainWindow?.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable window tabbing (removes "Show Tab Bar" / "Show All Tabs" from View menu)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Keep a reference to the main window and prevent it from being
        // deallocated when closed, so it can be shown again later.
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.isReleasedWhenClosed = false
                self.mainWindow = window
            }

            // Close extra windows that SwiftUI may have created
            let visible = NSApp.windows.filter { $0.isVisible }
            for window in visible.dropFirst() {
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
}
