import Foundation
#if canImport(VLCKitSPM)
import VLCKitSPM
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#endif

enum VideoProbeError: LocalizedError {
    case mediaCreationFailed
    case probeFailed
    case noTracksFound

    var errorDescription: String? {
        switch self {
        case .mediaCreationFailed: return "Could not open the file with VLCKit."
        case .probeFailed: return "VLCKit failed to read tracks from the file."
        case .noTracksFound: return "No audio or subtitle tracks were found."
        }
    }
}

/// Wraps VLCKit. For Step 1 only exposes track probing; playback comes later.
///
/// VLCKit 4.x dropped the `tracksInformation` dictionary API. Tracks are now
/// exposed on `VLCMediaPlayer` once playback opens, so we briefly play the
/// file (muted, no drawable) and read `audioTracks` + `textTracks`.
final class VideoPlayerEngine: NSObject {
    private let lock = NSLock()
    private var pending: CheckedContinuation<[MediaTrack], Error>?
    private var probePlayer: VLCMediaPlayer?

    func probeTracks(at url: URL) async throws -> [MediaTrack] {
        try await withCheckedThrowingContinuation { continuation in
            guard let media = VLCMedia(url: url) else {
                continuation.resume(throwing: VideoProbeError.mediaCreationFailed)
                return
            }
            let player = VLCMediaPlayer()
            player.media = media
            player.delegate = self
            player.audio?.volume = 0

            lock.lock()
            self.pending = continuation
            self.probePlayer = player
            lock.unlock()

            player.play()
        }
    }

    private func collectTracks(from player: VLCMediaPlayer) -> [MediaTrack] {
        var result: [MediaTrack] = []
        for (offset, track) in player.audioTracks.enumerated() {
            result.append(MediaTrack(
                id: offset,
                kind: .audio,
                language: nil,
                codec: nil,
                description: track.trackName
            ))
        }
        for (offset, track) in player.textTracks.enumerated() {
            result.append(MediaTrack(
                id: offset,
                kind: .subtitle,
                language: nil,
                codec: nil,
                description: track.trackName
            ))
        }
        return result
    }

    private func finish(tracks: [MediaTrack]) {
        lock.lock()
        let continuation = pending
        let player = probePlayer
        pending = nil
        probePlayer = nil
        lock.unlock()

        player?.stop()
        continuation?.resume(returning: tracks)
    }

    private func fail(_ error: Error) {
        lock.lock()
        let continuation = pending
        let player = probePlayer
        pending = nil
        probePlayer = nil
        lock.unlock()

        player?.stop()
        continuation?.resume(throwing: error)
    }
}

extension VideoPlayerEngine: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        switch player.state {
        case .playing:
            finish(tracks: collectTracks(from: player))
        case .error:
            fail(VideoProbeError.probeFailed)
        default:
            break
        }
    }
}
