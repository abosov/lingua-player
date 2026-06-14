import Foundation
#if canImport(VLCKitSPM)
import VLCKitSPM
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#endif

enum VideoProbeError: LocalizedError {
    case mediaCreationFailed
    case noTracksFound

    var errorDescription: String? {
        switch self {
        case .mediaCreationFailed: return "Could not open the file with VLCKit."
        case .noTracksFound: return "No audio or subtitle tracks were found."
        }
    }
}

/// Wraps VLCKit. For Step 1 only exposes track probing; playback comes later.
///
/// Uses VLCMedia.parse(options: [.parseLocal]) so no decoding happens — the
/// file is inspected purely for stream metadata. Result arrives via the
/// VLCMediaDelegate.mediaDidFinishParsing callback.
final class VideoPlayerEngine: NSObject {
    private let lock = NSLock()
    private var pending: CheckedContinuation<[MediaTrack], Error>?
    private var currentMedia: VLCMedia?

    func probeTracks(at url: URL) async throws -> [MediaTrack] {
        try await withCheckedThrowingContinuation { continuation in
            guard let media = VLCMedia(url: url) else {
                continuation.resume(throwing: VideoProbeError.mediaCreationFailed)
                return
            }
            media.delegate = self

            lock.lock()
            self.pending = continuation
            self.currentMedia = media
            lock.unlock()

            media.parse(options: [.parseLocal])
        }
    }

    // VLCKitSPM 4.x: VLCMediaTrack is an NSObject; its Obj-C properties are
    // not bridged into Swift directly, so we read them via KVC.
    //   type: NSNumber  — 0 audio, 1 video, 2 text
    //   language, trackDescription, codecName: NSString?
    private func extractTracks(from media: VLCMedia) -> [MediaTrack] {
        media.tracksInformation.enumerated().compactMap { index, track in
            guard let obj = track as? NSObject,
                  let type = obj.value(forKey: "type") as? Int
            else { return nil }

            let kind: MediaTrack.Kind
            switch type {
            case 0: kind = .audio
            case 2: kind = .subtitle
            default: return nil
            }

            return MediaTrack(
                id: index,
                kind: kind,
                source: .embedded,
                language: Self.nonEmptyString(obj, "language"),
                codec: Self.nonEmptyString(obj, "codecName"),
                description: Self.nonEmptyString(obj, "trackDescription")
            )
        }
    }

    private static func nonEmptyString(_ obj: NSObject, _ key: String) -> String? {
        guard let value = obj.value(forKey: key) as? String, !value.isEmpty else {
            return nil
        }
        return value
    }
}

extension VideoPlayerEngine: VLCMediaDelegate {
    func mediaDidFinishParsing(_ aMedia: VLCMedia) {
        lock.lock()
        let continuation = pending
        pending = nil
        currentMedia = nil
        lock.unlock()

        guard let continuation else { return }
        continuation.resume(returning: extractTracks(from: aMedia))
    }
}
