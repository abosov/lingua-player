import Foundation
import AppKit
#if canImport(VLCKitSPM)
import VLCKitSPM
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#endif

@MainActor
final class PlayerViewModel: NSObject, ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var activeChannel: Channel = .a
    @Published private(set) var cues: [SubtitleCue] = []
    @Published private(set) var currentCueIndex: Int? = nil
    @Published private(set) var subtitleStatus: String? = nil

    let drawableView: NSView
    private let setup: PlaybackSetup
    private let player: VLCMediaPlayer
    private var timer: Timer?
    private var didApplyInitialSelection = false

    init(setup: PlaybackSetup) {
        self.setup = setup

        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        self.drawableView = view

        let player = VLCMediaPlayer()
        self.player = player

        super.init()

        player.delegate = self
        if let media = VLCMedia(url: setup.fileURL) {
            player.media = media
        }
    }

    func start() {
        guard timer == nil else { return }
        player.play()
        startTimer()
        Task { await loadSubtitles() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
    }

    // MARK: Playback

    func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func seek(to seconds: TimeInterval) {
        let clamped = max(0, seconds)
        player.time = VLCTime(int: Int32(clamped * 1000))
        if !player.isPlaying {
            player.play()
        }
    }

    // MARK: Channels

    func toggleChannel() {
        activeChannel = (activeChannel == .a) ? .b : .a
        applyAudioSelection()
    }

    private func applyAudioSelection() {
        let target = (activeChannel == .a) ? setup.audioTrackAIndex : setup.audioTrackBIndex
        let tracks = player.audioTracks
        print("[PlayerViewModel] applyAudioSelection channel=\(activeChannel.label) target=\(target) tracks=\(tracks.count)")
        for (i, track) in tracks.enumerated() {
            print("  [\(i)] id=\(track.trackId) name=\(track.trackName) lang=\(track.language ?? "?") selected=\(track.isSelected)")
        }
        guard target >= 0, target < tracks.count else { return }
        // Exclusive selection: setting this to true unselects every other audio
        // track automatically — flipping per-track isSelected is unreliable.
        tracks[target].selectedExclusively = true
    }

    private func disableVLCSubtitleOverlay() {
        player.deselectAllTextTracks()
    }

    // MARK: Phrase navigation

    func previousPhrase() {
        let tolerance: TimeInterval = 0.15
        if let current = currentCue(at: currentTime) {
            if currentTime - current.startTime < tolerance {
                if let idx = cues.firstIndex(of: current), idx > 0 {
                    seek(to: cues[idx - 1].startTime)
                }
            } else {
                seek(to: current.startTime)
            }
            return
        }
        if let previous = cues.last(where: { $0.startTime < currentTime }) {
            seek(to: previous.startTime)
        }
    }

    func nextPhrase() {
        if let next = cues.first(where: { $0.startTime > currentTime + 0.05 }) {
            seek(to: next.startTime)
        }
    }

    var currentCueText: String? {
        guard let idx = currentCueIndex, idx >= 0, idx < cues.count else { return nil }
        return cues[idx].text
    }

    private func currentCue(at time: TimeInterval) -> SubtitleCue? {
        cues.first(where: { $0.startTime <= time && time <= $0.endTime })
    }

    // MARK: Subtitle loading

    private func loadSubtitles() async {
        subtitleStatus = "Extracting subtitles via ffmpeg…"
        let url = setup.fileURL
        let streamIndex = setup.subtitleTrackIndex
        do {
            let parsed = try await SubtitleParser.extractCues(
                fileURL: url,
                subtitleStreamIndex: streamIndex
            )
            cues = parsed
            subtitleStatus = parsed.isEmpty ? "No subtitle cues found." : nil
        } catch {
            subtitleStatus = error.localizedDescription
        }
    }

    // MARK: Polling

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        currentTime = TimeInterval(player.time.intValue) / 1000.0
        if duration == 0, let length = player.media?.length.intValue, length > 0 {
            duration = TimeInterval(length) / 1000.0
        }
        isPlaying = player.isPlaying
        currentCueIndex = cues.firstIndex { $0.startTime <= currentTime && currentTime <= $0.endTime }
    }
}

extension PlayerViewModel: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor in
            self.handleStateChange()
        }
    }

    // Audio tracks aren't enumerated by libvlc until shortly after playback
    // starts. This callback is the reliable signal that they're now selectable.
    nonisolated func mediaPlayerTrackAdded(_ trackId: String, withType trackType: VLCMedia.TrackType) {
        guard trackType == .audio else { return }
        Task { @MainActor in
            self.applyAudioSelection()
        }
    }

    private func handleStateChange() {
        if player.state == .playing && !didApplyInitialSelection {
            didApplyInitialSelection = true
            applyAudioSelection()
            disableVLCSubtitleOverlay()
            if let length = player.media?.length.intValue, length > 0 {
                duration = TimeInterval(length) / 1000.0
            }
        }
    }
}
