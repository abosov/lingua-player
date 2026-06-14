import Foundation
#if canImport(VLCKit)
import VLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#endif

enum VideoProbeError: LocalizedError {
    case parseFailed
    case noTracksFound

    var errorDescription: String? {
        switch self {
        case .parseFailed: return "VLCKit failed to parse the file."
        case .noTracksFound: return "No audio or subtitle tracks were found."
        }
    }
}

/// Wraps VLCKit. For Step 1 only exposes track probing; playback comes later.
final class VideoPlayerEngine: NSObject {
    private let lock = NSLock()
    private var pending: CheckedContinuation<[MediaTrack], Error>?
    private var currentMedia: VLCMedia?

    /// Parses the file and returns its audio + subtitle tracks.
    func probeTracks(at url: URL) async throws -> [MediaTrack] {
        try await withCheckedThrowingContinuation { continuation in
            let media = VLCMedia(url: url)
            media.delegate = self

            lock.lock()
            self.pending = continuation
            self.currentMedia = media
            lock.unlock()

            // Local parse, no network. Result delivered to mediaDidFinishParsing(_:).
            media.parse(options: [.parseLocal])
        }
    }

    private func extractTracks(from media: VLCMedia) -> [MediaTrack] {
        guard let raw = media.tracksInformation as? [[String: Any]] else {
            return []
        }
        return raw.compactMap(Self.makeTrack(from:))
    }

    private static func makeTrack(from dict: [String: Any]) -> MediaTrack? {
        guard let type = dict[VLCMediaTracksInformationType] as? String else {
            return nil
        }
        let kind: MediaTrack.Kind
        switch type {
        case VLCMediaTracksInformationTypeAudio:
            kind = .audio
        case VLCMediaTracksInformationTypeText:
            kind = .subtitle
        default:
            return nil
        }
        let id = (dict[VLCMediaTracksInformationId] as? NSNumber)?.intValue ?? -1
        let language = (dict[VLCMediaTracksInformationLanguage] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let description = (dict[VLCMediaTracksInformationDescription] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let codec = (dict[VLCMediaTracksInformationCodec] as? NSNumber)
            .map { fourCCString($0.uint32Value) }
            .flatMap { $0.isEmpty ? nil : $0 }
        return MediaTrack(
            id: id,
            kind: kind,
            language: language,
            codec: codec,
            description: description
        )
    }

    private static func fourCCString(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        let scalars = bytes.compactMap { byte -> UnicodeScalar? in
            guard byte >= 0x20, byte < 0x7F else { return nil }
            return UnicodeScalar(byte)
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespaces)
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
        let tracks = extractTracks(from: aMedia)
        continuation.resume(returning: tracks)
    }
}
