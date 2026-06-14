import Foundation

enum MediaPreparationError: LocalizedError {
    case ffmpegNotFound
    case launchFailed(String)
    case remuxFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found at /usr/local/bin/ffmpeg or /opt/homebrew/bin/ffmpeg. Install via Homebrew: brew install ffmpeg"
        case .launchFailed(let msg):
            return "Could not launch ffmpeg: \(msg)"
        case .remuxFailed(let code, let stderr):
            let snippet = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "ffmpeg remux failed (exit \(code))" + (snippet.isEmpty ? "" : ": \(snippet)")
        }
    }
}

/// Remuxes a source video into a temporary MP4 containing the original video
/// plus the two selected audio tracks, ready for AVPlayer.
///
/// We bypass AVFoundation's MKV limitation by stream-copying (`-c copy`) into
/// MP4 — no re-encoding, so this runs in seconds even for full-length video.
/// AVPlayer then sees a normal MP4 with two audio tracks exposed via the
/// AVMediaSelectionGroup API, which is what enables instant audio switching.
enum MediaPreparer {
    private static let ffmpegCandidates = [
        "/usr/local/bin/ffmpeg",
        "/opt/homebrew/bin/ffmpeg"
    ]

    static var temporaryRemuxURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lingua_temp.mp4")
    }

    /// Remuxes `source` into the temporary MP4 and returns its URL.
    ///
    /// `audioTrackAIndex` / `audioTrackBIndex` are 0-based positions in the
    /// source's *audio-only* track list, matching what StreamSetupViewModel
    /// stores. ffmpeg's `0:a:N` selector uses the same numbering, so no
    /// translation is needed — `0:a:0` picks the first audio stream
    /// regardless of where video or subtitle streams sit in the container.
    static func remux(
        source: URL,
        audioTrackAIndex: Int,
        audioTrackBIndex: Int
    ) async throws -> URL {
        let ffmpeg = try locateFFmpeg()
        let output = temporaryRemuxURL

        let args = [
            "-nostdin",
            "-loglevel", "error",
            "-i", source.path,
            "-map", "0:v",
            "-map", "0:a:\(audioTrackAIndex)",
            "-map", "0:a:\(audioTrackBIndex)",
            "-c", "copy",
            "-y",
            output.path
        ]
        try await run(executable: ffmpeg, args: args)
        return output
    }

    static func removeTemporaryRemuxFile() {
        try? FileManager.default.removeItem(at: temporaryRemuxURL)
    }

    private static func locateFFmpeg() throws -> String {
        for path in ffmpegCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw MediaPreparationError.ffmpegNotFound
    }

    private static func run(executable: String, args: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: MediaPreparationError.launchFailed(error.localizedDescription))
                    return
                }
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    let msg = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: MediaPreparationError.remuxFailed(process.terminationStatus, msg))
                    return
                }
                continuation.resume()
            }
        }
    }
}
