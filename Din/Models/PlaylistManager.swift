import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PlaylistManager: ObservableObject {
    static let shared = PlaylistManager()

    @Published var tracks: [Track] = []
    @Published private(set) var currentTrackID: Track.ID?
    @Published var isPlaying = false
    @Published var volume: Float = 0.75
    @Published var repeatEnabled = false
    @Published var selection: Set<Track.ID> = []

    /// Waveform peak data for the current track. Empty array if not yet available.
    @Published var waveformPeaks: [Float] = []

    /// Whether waveform data has been generated for the current track.
    @Published var isWaveformReady = false

    /// Live playback time — NOT @Published so it doesn't trigger view re-renders.
    private(set) var currentTime: TimeInterval = 0

    /// Live time for UI display — reads directly from the player for accuracy.
    var displayTime: TimeInterval {
        guard let player else { return currentTime }
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? seconds : currentTime
    }

    var currentIndex: Int? {
        get {
            guard let id = currentTrackID else { return nil }
            return tracks.firstIndex { $0.id == id }
        }
        set {
            if let i = newValue, tracks.indices.contains(i) {
                currentTrackID = tracks[i].id
            } else {
                currentTrackID = nil
            }
        }
    }

    private var player: AVQueuePlayer?
    private var timer: Timer?
    private var tickCount = 0
    private var _suppressUndo = false
    private var waveformTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?

    var currentTrack: Track? {
        guard let id = currentTrackID else { return nil }
        return tracks.first { $0.id == id }
    }

    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var hasContent: Bool { !tracks.isEmpty }

    init() {
        restoreState()
        setupRemoteCommands()
    }

    // MARK: - Undo

    private var undoManager: UndoManager? {
        NSApp.keyWindow?.undoManager ?? NSApp.windows.first?.undoManager
    }

    private func registerUndoSnapshot() {
        guard !_suppressUndo else { return }
        guard let undoManager else { return }
        let oldTracks = tracks
        let oldID = currentTrackID
        let oldSelection = selection
        undoManager.registerUndo(withTarget: self) { mgr in
            let playingID = mgr.currentTrackID
            mgr.registerUndoSnapshot()  // register redo
            mgr.tracks = oldTracks
            mgr.currentTrackID = oldID
            mgr.selection = oldSelection
            if oldID != playingID && mgr.isPlaying {
                mgr.stop()
            }
            mgr.saveState()
        }
    }

    // MARK: - Playback Controls

    func play() {
        if currentIndex == nil && !tracks.isEmpty {
            playTrack(at: 0)
            return
        }
        if player == nil, let track = currentTrack {
            let resumeTime = currentTime
            loadAndPlay(track: track)
            if resumeTime > 0 {
                seek(to: resumeTime)
            }
            return
        }
        player?.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        saveState()
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func next() {
        guard !tracks.isEmpty else { return }
        if let current = currentIndex {
            let nextIndex = current + 1
            if nextIndex < tracks.count {
                playTrack(at: nextIndex)
            } else if repeatEnabled {
                playTrack(at: 0)
            } else {
                stop()
                currentIndex = 0
            }
        } else {
            playTrack(at: 0)
        }
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        if displayTime > 3, let idx = currentIndex {
            playTrack(at: idx)
            return
        }
        if let current = currentIndex {
            let prevIndex = current - 1
            if prevIndex >= 0 {
                playTrack(at: prevIndex)
            } else if repeatEnabled {
                playTrack(at: tracks.count - 1)
            } else {
                playTrack(at: 0)
            }
        } else {
            playTrack(at: 0)
        }
    }

    func playTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        currentIndex = index
        loadAndPlay(track: tracks[index])
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateNowPlayingInfo()
    }

    func skipForward(by seconds: TimeInterval = 5) {
        let target = min(displayTime + seconds, currentTrack?.duration ?? displayTime)
        seek(to: target)
    }

    func skipBackward(by seconds: TimeInterval = 5) {
        let target = max(displayTime - seconds, 0)
        seek(to: target)
    }

    func setVolume(_ vol: Float) {
        volume = vol
        player?.volume = vol
        saveState()
    }

    func toggleRepeat() {
        repeatEnabled.toggle()
        saveState()
    }

    // MARK: - Playlist Management

    func addTracks(urls: [URL], at index: Int? = nil) {
        registerUndoSnapshot()
        let audioURLs = MetadataLoader.audioFiles(in: urls)
        guard !audioURLs.isEmpty else { return }

        let insertionIndex = index ?? tracks.count
        let placeholders = audioURLs.map { Track(url: $0) }
        tracks.insert(contentsOf: placeholders, at: min(insertionIndex, tracks.count))

        let startIndex = insertionIndex
        for (offset, url) in audioURLs.enumerated() {
            Task {
                let track = await MetadataLoader.load(url: url)
                let targetIndex = startIndex + offset
                if targetIndex < tracks.count, tracks[targetIndex].url == url {
                    tracks[targetIndex].title = track.title
                    tracks[targetIndex].artist = track.artist
                    tracks[targetIndex].album = track.album
                    tracks[targetIndex].duration = track.duration
                }
            }
        }
        saveState()
    }

    func removeTracks(ids: Set<Track.ID>) {
        registerUndoSnapshot()
        let wasPlaying = isPlaying
        let removingCurrent = currentTrackID.map { ids.contains($0) } ?? false
        let oldIndex = currentIndex ?? 0

        tracks.removeAll { ids.contains($0.id) }
        selection.subtract(ids)

        if removingCurrent {
            stop()
            if !tracks.isEmpty {
                let newIndex = min(oldIndex, tracks.count - 1)
                currentTrackID = tracks[newIndex].id
                if wasPlaying { play() }
            } else {
                currentTrackID = nil
            }
        }
        saveState()
    }

    func clearPlaylist() {
        registerUndoSnapshot()
        stop()
        tracks.removeAll()
        currentTrackID = nil
        selection.removeAll()
        saveState()
    }

    func replacePlaylist(urls: [URL]) {
        registerUndoSnapshot()
        _suppressUndo = true
        clearPlaylist()
        addTracks(urls: urls)
        _suppressUndo = false
        if !tracks.isEmpty {
            playTrack(at: 0)
        }
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        registerUndoSnapshot()
        tracks.move(fromOffsets: source, toOffset: destination)
        saveState()
    }

    // MARK: - M3U8 Save/Load

    func savePlaylistToFile() {
        guard !tracks.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
        panel.nameFieldStringValue = "Playlist.m3u8"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = M3U8.write(tracks: tracks)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func loadPlaylistFromFile(replace: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadPlaylistFromURL(url, replace: replace)
        RecentItems.shared.addPlaylist(url)
    }

    func loadPlaylistFromURL(_ url: URL, replace: Bool) {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
        let baseURL = url.deletingLastPathComponent()
        let urls = M3U8.parse(contents: contents, relativeTo: baseURL)
        guard !urls.isEmpty else { return }
        if replace {
            replacePlaylist(urls: urls)
        } else {
            addTracks(urls: urls)
        }
    }

    // MARK: - Persistence

    func saveState() {
        let defaults = UserDefaults.standard
        defaults.set(tracks.map { $0.url.absoluteString }, forKey: "din.playlist")
        defaults.set(currentIndex ?? -1, forKey: "din.currentIndex")
        defaults.set(displayTime, forKey: "din.currentTime")
        defaults.set(Double(volume), forKey: "din.volume")
        defaults.set(repeatEnabled, forKey: "din.repeat")
    }

    private func restoreState() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: "din.volume") != nil {
            volume = Float(defaults.double(forKey: "din.volume"))
        }
        repeatEnabled = defaults.bool(forKey: "din.repeat")

        guard let urlStrings = defaults.stringArray(forKey: "din.playlist") else { return }
        let urls = urlStrings.compactMap { URL(string: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }

        tracks = urls.map { Track(url: $0) }

        for (index, url) in urls.enumerated() {
            Task {
                let track = await MetadataLoader.load(url: url)
                if index < self.tracks.count, self.tracks[index].url == url {
                    self.tracks[index].title = track.title
                    self.tracks[index].artist = track.artist
                    self.tracks[index].album = track.album
                    self.tracks[index].duration = track.duration
                }
            }
        }

        let savedIndex = defaults.integer(forKey: "din.currentIndex")
        if savedIndex >= 0, tracks.indices.contains(savedIndex) {
            currentIndex = savedIndex
            // Pre-generate waveform for the restored track
            generateWaveform(for: tracks[savedIndex].url)
        }
        currentTime = defaults.double(forKey: "din.currentTime")
    }

    // MARK: - Media Keys

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in PlaylistManager.shared.play() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in PlaylistManager.shared.pause() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in PlaylistManager.shared.togglePlayPause() }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { _ in
            Task { @MainActor in PlaylistManager.shared.next() }
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { _ in
            Task { @MainActor in PlaylistManager.shared.previous() }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in PlaylistManager.shared.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        if let track = currentTrack {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: track.title,
                MPMediaItemPropertyPlaybackDuration: track.duration,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: displayTime,
                MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            ]
            if track.artist != "Unknown Artist" {
                info[MPMediaItemPropertyArtist] = track.artist
            }
            if track.album != "Unknown Album" {
                info[MPMediaItemPropertyAlbumTitle] = track.album
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }

    // MARK: - Private

    private func loadAndPlay(track: Track) {
        stop()

        let item = AVPlayerItem(url: track.url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.volume = volume
        player = queuePlayer

        // Queue the next track for gapless playback
        enqueueNextTrack()

        // Observe when the current item finishes playing
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let finishedItem = notification.object as? AVPlayerItem else { return }
                // Only handle if this notification is for an item in our player
                guard self.player != nil else { return }
                self.handleItemDidFinish(finishedItem)
            }
        }

        queuePlayer.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
        generateWaveform(for: track.url)
    }

    /// Enqueue the next track in the AVQueuePlayer for gapless playback.
    private func enqueueNextTrack() {
        guard let player else { return }
        guard let idx = currentIndex else { return }
        let nextIndex = idx + 1
        guard nextIndex < tracks.count else {
            if repeatEnabled && !tracks.isEmpty {
                let nextItem = AVPlayerItem(url: tracks[0].url)
                player.insert(nextItem, after: nil)
            }
            return
        }
        let nextItem = AVPlayerItem(url: tracks[nextIndex].url)
        player.insert(nextItem, after: nil)
    }

    /// Called when an AVPlayerItem finishes. AVQueuePlayer automatically advances
    /// to the next queued item (gapless), so we just update our tracking state.
    private func handleItemDidFinish(_ finishedItem: AVPlayerItem) {
        guard let idx = currentIndex else { return }
        let nextIndex = idx + 1

        if nextIndex < tracks.count {
            // AVQueuePlayer has already advanced to the next item
            currentIndex = nextIndex
            currentTime = 0
            updateNowPlayingInfo()
            generateWaveform(for: tracks[nextIndex].url)
            // Queue the track after that for continued gapless playback
            enqueueNextTrack()
        } else if repeatEnabled && !tracks.isEmpty {
            // AVQueuePlayer advanced to the repeat item we queued
            currentIndex = 0
            currentTime = 0
            updateNowPlayingInfo()
            generateWaveform(for: tracks[0].url)
            enqueueNextTrack()
        } else {
            // End of playlist
            stop()
            currentIndex = 0
        }
    }

    private func generateWaveform(for url: URL) {
        waveformTask?.cancel()
        waveformPeaks = []
        isWaveformReady = false

        waveformTask = Task {
            do {
                let peaks = try await WaveformGenerator.shared.peaksStreaming(for: url) { partial in
                    self.waveformPeaks = partial
                }
                guard !Task.isCancelled else { return }
                self.waveformPeaks = peaks
                self.isWaveformReady = true

                // TODO: Re-enable after testing streaming generation
                // self.prefetchNextTrackWaveform()
            } catch {
                guard !Task.isCancelled else { return }
                self.waveformPeaks = []
                self.isWaveformReady = false
            }
        }
    }

    private func prefetchNextTrackWaveform() {
        guard let idx = currentIndex else { return }
        let nextIndex = idx + 1
        guard nextIndex < tracks.count else { return }
        let nextURL = tracks[nextIndex].url
        Task {
            await WaveformGenerator.shared.prefetch(url: nextURL)
        }
    }

    private func stop() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player?.pause()
        player?.removeAllItems()
        player = nil
        isPlaying = false
        currentTime = 0
        stopTimer()
        updateNowPlayingInfo()
        waveformTask?.cancel()
        waveformTask = nil
    }

    private func startTimer() {
        stopTimer()
        tickCount = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let p = self.player {
                    let seconds = CMTimeGetSeconds(p.currentTime())
                    if seconds.isFinite {
                        self.currentTime = seconds
                    }
                }
                self.tickCount += 1
                if self.tickCount % 20 == 0 {
                    self.saveState()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
