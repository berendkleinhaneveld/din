import SwiftUI
import UniformTypeIdentifiers

@main
struct BoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
        if replace {
            PlaylistManager.shared.replacePlaylist(urls: panel.urls)
        } else {
            PlaylistManager.shared.addTracks(urls: panel.urls)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            PlaylistManager.shared.replacePlaylist(urls: urls)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            PlaylistManager.shared.saveState()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = sender.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable window tabbing (removes "Show Tab Bar" / "Show All Tabs" from View menu)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Close extra windows that SwiftUI may have created
        DispatchQueue.main.async {
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
                   let hitView = contentView.hitTest(event.locationInWindow) {
                    var view: NSView? = hitView
                    while let v = view {
                        if v is NSTableRowView {
                            Task { @MainActor in
                                let mgr = PlaylistManager.shared
                                if let selectedID = mgr.selection.first,
                                   let index = mgr.tracks.firstIndex(where: { $0.id == selectedID }) {
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
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])

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
                       let index = mgr.tracks.firstIndex(where: { $0.id == selectedID }) {
                        mgr.playTrack(at: index)
                    }
                }
                return nil
            default:
                break
            }

            return event
        }

        // Media keys (F7/F8/F9 or equivalent) — delivered as system-defined events
        NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { event in
            guard event.subtype.rawValue == 8 else { return event }
            let keyCode = (event.data1 & 0xFFFF0000) >> 16
            let keyDown = (event.data1 & 0x0000FF00) == 0x0A00
            guard keyDown else { return event }

            switch keyCode {
            case 16: // Play/Pause
                Task { @MainActor in PlaylistManager.shared.togglePlayPause() }
                return nil
            case 19: // Next
                Task { @MainActor in PlaylistManager.shared.next() }
                return nil
            case 20: // Previous
                Task { @MainActor in PlaylistManager.shared.previous() }
                return nil
            default:
                return event
            }
        }
    }
}
