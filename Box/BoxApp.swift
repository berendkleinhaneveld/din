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

        // Keyboard shortcuts: Space = play/pause, [ = previous, ] = next
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            guard modifiers.isEmpty else { return event }

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
            default:
                return event
            }
        }
    }
}
