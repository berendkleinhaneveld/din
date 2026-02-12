import Foundation

@MainActor
final class RecentItems: ObservableObject {
    static let shared = RecentItems()

    private static let maxItems = 12
    private static let filesKey = "din.recentFiles"
    private static let playlistsKey = "din.recentPlaylists"

    @Published var recentFiles: [String] = []
    @Published var recentPlaylists: [String] = []

    init() {
        let defaults = UserDefaults.standard
        recentFiles = defaults.stringArray(forKey: Self.filesKey) ?? []
        recentPlaylists = defaults.stringArray(forKey: Self.playlistsKey) ?? []
    }

    func addFile(_ url: URL) {
        add(url.path, to: &recentFiles, key: Self.filesKey)
    }

    func addPlaylist(_ url: URL) {
        add(url.path, to: &recentPlaylists, key: Self.playlistsKey)
    }

    func remove(_ path: String) {
        recentFiles.removeAll { $0 == path }
        recentPlaylists.removeAll { $0 == path }
        save()
    }

    func clearAll() {
        recentFiles.removeAll()
        recentPlaylists.removeAll()
        save()
    }

    static func displayName(for path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func add(_ path: String, to list: inout [String], key: String) {
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        if list.count > Self.maxItems {
            list = Array(list.prefix(Self.maxItems))
        }
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(recentFiles, forKey: Self.filesKey)
        defaults.set(recentPlaylists, forKey: Self.playlistsKey)
    }
}
