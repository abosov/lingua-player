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
    private var itemStatusObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var stalledObserver: NSObjectProtocol?
    private var failedToPlayObserver: NSObjectProtocol?
    private var audioSelectionGroup: AVMediaSelectionGroup?
    private var audioOptions: [AVMediaSelectionOption] = []

    init(setup: PlaybackSetup) {
        self.remuxedURL = setup.remuxedURL
        self.cues = setup.cues
        Self.reportInputFile(at: setup.remuxedURL)
        let item = AVPlayerItem(url: setup.remuxedURL)
        self.player = AVPlayer(playerItem: item)
        super.init()
        startTimeObserver()
        observeRate()
        observeItemStatus(item)
        observePlayerStatus()
        observeTimeControl()
        observeFailureNotifications(for: item)
        Task { await loadAudioOptions(for: item) }
        Task { await dumpAssetTrackInfo(item) }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
        }
        if let failedToPlayObserver {
            NotificationCenter.default.removeObserver(failedToPlayObserver)
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
        // First press inside a cue (>2s in) replays the current cue; a second
        // press within the first two seconds walks back to the previous cue.
        let rewindThreshold: TimeInterval = 2.0
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
            print("[Remux] AVPlayer.rate changed → \(player.rate) (isPlaying=\(playing))")
            Task { @MainActor [weak self] in
                self?.isPlaying = playing
            }
        }
    }

    private func observeItemStatus(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            let name: String
            switch item.status {
            case .unknown: name = "unknown"
            case .readyToPlay: name = "readyToPlay"
            case .failed: name = "failed"
            @unknown default: name = "unknown(@unknown)"
            }
            print("[Remux] AVPlayerItem.status → \(name)")
            if item.status == .failed {
                if let error = item.error as NSError? {
                    print("[Remux] AVPlayerItem.error: domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription)")
                    print("[Remux] AVPlayerItem.error userInfo: \(error.userInfo)")
                }
                if let log = item.errorLog() {
                    for event in log.events {
                        print("[Remux] errorLog: domain=\(event.errorDomain) code=\(event.errorStatusCode) comment=\(event.errorComment ?? "nil")")
                    }
                }
            }
            if let access = item.accessLog() {
                for event in access.events {
                    print("[Remux] accessLog: indicatedBitrate=\(event.indicatedBitrate) observedBitrate=\(event.observedBitrate) errors=\(event.numberOfMediaRequests)")
                }
            }
            _ = self
        }
    }

    private func observePlayerStatus() {
        playerStatusObservation = player.observe(\.status, options: [.new, .initial]) { [weak self] player, _ in
            let name: String
            switch player.status {
            case .unknown: name = "unknown"
            case .readyToPlay: name = "readyToPlay"
            case .failed: name = "failed"
            @unknown default: name = "unknown(@unknown)"
            }
            print("[Remux] AVPlayer.status → \(name)")
            if player.status == .failed, let error = player.error as NSError? {
                print("[Remux] AVPlayer.error: domain=\(error.domain) code=\(error.code) desc=\(error.localizedDescription)")
            }
            _ = self
        }
    }

    private func observeTimeControl() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            let name: String
            switch player.timeControlStatus {
            case .paused: name = "paused"
            case .waitingToPlayAtSpecifiedRate:
                let reason = player.reasonForWaitingToPlay?.rawValue ?? "nil"
                name = "waitingToPlayAtSpecifiedRate(\(reason))"
            case .playing: name = "playing"
            @unknown default: name = "unknown"
            }
            print("[Remux] AVPlayer.timeControlStatus → \(name)")
        }
    }

    private func observeFailureNotifications(for item: AVPlayerItem) {
        failedToPlayObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { note in
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            print("[Remux] AVPlayerItemFailedToPlayToEndTime: \(err?.localizedDescription ?? "nil") userInfo=\(err?.userInfo ?? [:])")
        }
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { _ in
            print("[Remux] AVPlayerItemPlaybackStalled")
        }
    }

    private static func reportInputFile(at url: URL) {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        if exists {
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1
            print("[Remux] AVPlayer input: exists=true size=\(size) bytes path=\(url.path)")
        } else {
            print("[Remux] AVPlayer input: MISSING path=\(url.path)")
        }
    }

    private func dumpAssetTrackInfo(_ item: AVPlayerItem) async {
        let asset = item.asset
        do {
            let tracks = try await asset.load(.tracks)
            print("[Remux] asset.tracks count=\(tracks.count)")
            for (i, track) in tracks.enumerated() {
                let mediaType = track.mediaType.rawValue
                let isEnabled = (try? await track.load(.isEnabled)) ?? false
                let timeRange = try? await track.load(.timeRange)
                let format = (try? await track.load(.formatDescriptions)) ?? []
                let codec = format.first.map { CMFormatDescriptionGetMediaSubType($0) } ?? 0
                let codecStr = codec == 0 ? "?" : fourCharString(codec)
                let rangeStart = timeRange?.start.seconds ?? -1
                let rangeEnd = timeRange.map { CMTimeAdd($0.start, $0.duration).seconds } ?? -1
                print("[Remux]   track[\(i)] type=\(mediaType) codec=\(codecStr) enabled=\(isEnabled) range=\(rangeStart)..\(rangeEnd)")
            }
            let duration = try await asset.load(.duration)
            print("[Remux] asset.duration = \(CMTimeGetSeconds(duration))s")
            let playable = try await asset.load(.isPlayable)
            let readable = try await asset.load(.isReadable)
            print("[Remux] asset.isPlayable=\(playable) isReadable=\(readable)")
        } catch {
            print("[Remux] asset load error: \(error.localizedDescription)")
        }
    }

    private nonisolated func fourCharString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "?"
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
