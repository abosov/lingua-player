import Foundation
import AVFoundation

@MainActor
final class PlayerViewModel: NSObject, ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var activeChannel: Channel = .a
    @Published private(set) var cues: [SubtitleCue] = []
    @Published private(set) var currentCueIndex: Int? = nil

    let player: AVPlayer
    private let remuxedURL: URL
    private var timeObserver: Any?
    private var rateObservation: NSKeyValueObservation?
    private var audioSelectionGroup: AVMediaSelectionGroup?
    private var audioOptions: [AVMediaSelectionOption] = []

    init(setup: PlaybackSetup) {
        self.remuxedURL = setup.remuxedURL
        self.cues = setup.cues
        let item = AVPlayerItem(url: setup.remuxedURL)
        self.player = AVPlayer(playerItem: item)
        super.init()
        startTimeObserver()
        observeRate()
        Task { await loadAudioOptions(for: item) }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        // Clean up the temp remuxed MP4 so we don't leak it between sessions.
        try? FileManager.default.removeItem(at: remuxedURL)
    }

    func start() {
        player.play()
    }

    func stop() {
        player.pause()
    }

    // MARK: Playback

    func togglePlayback() {
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
    }

    func seek(to seconds: TimeInterval) {
        let clamped = max(0, seconds)
        let target = CMTime(seconds: clamped, preferredTimescale: 600)
        // Phrase boundaries are exact — disallow seek tolerance so we never
        // land mid-cue. Resume playback after the seek completes.
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in self?.player.play() }
        }
    }

    // MARK: Channels

    func toggleChannel() {
        activeChannel = (activeChannel == .a) ? .b : .a
        applyAudioSelection()
    }

    private func loadAudioOptions(for item: AVPlayerItem) async {
        do {
            let asset = item.asset
            guard let group = try await asset.loadMediaSelectionGroup(for: .audible) else {
                print("[PlayerViewModel] no audible media selection group on asset")
                return
            }
            let options = group.options
            print("[PlayerViewModel] audio options: \(options.count)")
            for (i, opt) in options.enumerated() {
                print("  [\(i)] \(opt.displayName) lang=\(opt.extendedLanguageTag ?? "?")")
            }
            audioSelectionGroup = group
            audioOptions = options
            applyAudioSelection()
        } catch {
            print("[PlayerViewModel] loadAudioOptions error: \(error.localizedDescription)")
        }
    }

    // The remuxed file always has Channel A's source as audio[0] and Channel
    // B's source as audio[1] — that ordering was fixed by MediaPreparer's
    // `-map 0:a:A -map 0:a:B` argument order.
    private func applyAudioSelection() {
        let target = (activeChannel == .a) ? 0 : 1
        guard let group = audioSelectionGroup,
              audioOptions.indices.contains(target) else { return }
        player.currentItem?.select(audioOptions[target], in: group)
        print("[PlayerViewModel] selected audio [\(target)] = \(audioOptions[target].displayName)")
    }

    // MARK: Phrase navigation

    func previousPhrase() {
        // First press inside a cue (>1s in) replays the current cue; a second
        // press within the first second walks back to the previous cue.
        let rewindThreshold: TimeInterval = 1.0
        if let current = currentCue(at: currentTime) {
            if currentTime - current.startTime < rewindThreshold {
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

    // MARK: Observers

    private func startTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.tick(time: time) }
        }
    }

    private func observeRate() {
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let playing = player.rate > 0
            Task { @MainActor [weak self] in
                self?.isPlaying = playing
            }
        }
    }

    private func tick(time: CMTime) {
        currentTime = CMTimeGetSeconds(time)
        if duration == 0, let item = player.currentItem {
            let dur = CMTimeGetSeconds(item.duration)
            if dur.isFinite, dur > 0 { duration = dur }
        }
        currentCueIndex = cues.firstIndex { $0.startTime <= currentTime && currentTime <= $0.endTime }
    }
}
