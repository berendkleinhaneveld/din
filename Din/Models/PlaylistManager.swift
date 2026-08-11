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

    /// The item currently playing, and the one queued behind it for gapless
    /// playback. Tracked so the end-of-item notification — which is posted for
    /// every `AVPlayerItem` in the process — can be matched against the item we
    /// are actually waiting on instead of advancing the playlist on any item.
    private var playingItem: AVPlayerItem?
    private var queuedItem: AVPlayerItem?

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

    /// Always resolve to the same window's undo manager.
    ///
    /// Keying off `keyWindow` is unreliable: while a drag is in flight from
    /// another app, or while the volume popover is key, it resolves to a
    /// different manager — or to nil, which silently drops the snapshot and
    /// makes the next undo jump two operations back.
    private var undoManager: UndoManager? {
        NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }?.undoManager
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
        let target = displayTime + seconds
        // Duration is 0 until metadata finishes loading; clamping to it then
        // would seek to the start of the track instead of skipping forward.
        let limit = trackDuration
        seek(to: limit > 0 ? min(target, limit) : target)
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
        // The look-ahead item was queued under the previous setting: on the last
        // track, enabling repeat had no effect until the next load, and disabling
        // it still wrapped around to track one.
        resyncQueue()
        saveState()
    }

    /// Duration of the current track, falling back to the player's own value
    /// while metadata is still loading.
    private var trackDuration: TimeInterval {
        if let duration = currentTrack?.duration, duration > 0 {
            return duration
        }
        guard let seconds = player?.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 else {
            return 0
        }
        return seconds
    }

    // MARK: - Playlist Management

    func addTracks(urls: [URL], at index: Int? = nil) {
        let audioURLs = MetadataLoader.audioFiles(in: urls)
        // Snapshot only once we know something will actually change, otherwise
        // dropping a non-audio file leaves a no-op entry on the undo stack.
        guard !audioURLs.isEmpty else { return }
        registerUndoSnapshot()

        // Clamp once and reuse: the insert was previously clamped while the
        // metadata writes below used the raw value, so an out-of-range index
        // sent the loaded titles and durations to the wrong rows.
        let insertionIndex = min(max(index ?? tracks.count, 0), tracks.count)
        let placeholders = audioURLs.map { Track(url: $0) }
        tracks.insert(contentsOf: placeholders, at: insertionIndex)

        for (offset, url) in audioURLs.enumerated() {
            Task {
                let track = await MetadataLoader.load(url: url)
                let targetIndex = insertionIndex + offset
                if targetIndex < tracks.count, tracks[targetIndex].url == url {
                    tracks[targetIndex].title = track.title
                    tracks[targetIndex].artist = track.artist
                    tracks[targetIndex].album = track.album
                    tracks[targetIndex].duration = track.duration
                }
            }
        }
        resyncQueue()
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
        } else {
            // Removing tracks around the current one changes what plays next.
            resyncQueue()
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
        // Resolve the audio files up front. Without this, dropping a document or
        // a folder with no audio in it clears the playlist and replaces it with
        // nothing, because `clearPlaylist` runs before `addTracks` discovers
        // there was nothing to add.
        let audioURLs = MetadataLoader.audioFiles(in: urls)
        guard !audioURLs.isEmpty else { return }

        registerUndoSnapshot()
        _suppressUndo = true
        clearPlaylist()
        addTracks(urls: audioURLs)
        _suppressUndo = false
        if !tracks.isEmpty {
            playTrack(at: 0)
        }
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        registerUndoSnapshot()
        tracks.move(fromOffsets: source, toOffset: destination)
        // Reordering changes which track follows the current one.
        resyncQueue()
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
                // Falls back to the player's duration so the Now Playing scrubber
                // isn't stuck at zero while metadata is still loading.
                MPMediaItemPropertyPlaybackDuration: trackDuration,
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
        playingItem = item

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
                // This notification fires for every AVPlayerItem in the process,
                // including ones we have already discarded, so only advance when
                // it is the item we are actually waiting on.
                guard self.player != nil, finishedItem === self.playingItem else { return }
                self.handleItemDidFinish(finishedItem)
            }
        }

        queuePlayer.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
        generateWaveform(for: track.url)
    }

    /// The track that should play after the current one, honouring repeat.
    private var nextTrackURL: URL? {
        guard let idx = currentIndex else { return nil }
        let nextIndex = idx + 1
        if nextIndex < tracks.count {
            return tracks[nextIndex].url
        }
        return repeatEnabled ? tracks.first?.url : nil
    }

    /// Enqueue the next track in the AVQueuePlayer for gapless playback.
    private func enqueueNextTrack() {
        queuedItem = nil
        guard let player, let nextURL = nextTrackURL else { return }
        let nextItem = AVPlayerItem(url: nextURL)
        player.insert(nextItem, after: nil)
        queuedItem = nextItem
    }

    /// Re-align the player's look-ahead queue with the playlist.
    ///
    /// The next track is queued the moment the current one starts, so any edit
    /// afterwards — reorder, insert, remove, or toggling repeat — leaves a stale
    /// item queued and the wrong track plays next. Left alone when the queued
    /// item is already correct, so an item that has begun buffering for a gapless
    /// transition isn't discarded and rebuilt for nothing.
    private func resyncQueue() {
        guard let player, player.currentItem != nil else { return }
        let queuedURL = (queuedItem?.asset as? AVURLAsset)?.url
        guard queuedURL != nextTrackURL else { return }

        for item in player.items().dropFirst() {
            player.remove(item)
        }
        enqueueNextTrack()
    }

    /// Called when an AVPlayerItem finishes. AVQueuePlayer automatically advances
    /// to the next queued item (gapless), so we just update our tracking state.
    private func handleItemDidFinish(_ finishedItem: AVPlayerItem) {
        guard let idx = currentIndex else { return }
        let nextIndex = idx + 1

        // The item AVQueuePlayer just advanced to is the one we queued behind
        // the finished track; it becomes the item we now wait on.
        playingItem = queuedItem
        queuedItem = nil

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
        playingItem = nil
        queuedItem = nil
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
