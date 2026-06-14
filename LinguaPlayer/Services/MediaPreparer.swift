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
            return "ffmpeg failed (exit \(code))" + (snippet.isEmpty ? "" : ": \(snippet)")
        }
    }
}

/// Remuxes a source video into a temporary MP4 containing the original video
/// plus the two selected audio tracks, ready for AVPlayer.
///
/// We first try stream-copy (`-c copy`) so the typical MKV→MP4 case takes a
/// few seconds. AVI containers often carry codecs MP4 can't host (Xvid,
/// DivX, MPEG-4 ASP), so on copy failure we fall back to a re-encode with
/// libx264 + AAC. AVPlayer then sees a normal MP4 with two audio tracks
/// exposed via the AVMediaSelectionGroup API.
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
    /// stores. ffmpeg's `0:a:N` selector uses the same numbering.
    ///
    /// `onReencodeStart` fires (once) when the fast copy path fails and we
    /// switch to the slower re-encode path — the caller can use it to update
    /// progress UI ("Converting video…").
    static func remux(
        source: URL,
        audioTrackAIndex: Int,
        audioTrackBIndex: Int,
        onReencodeStart: @Sendable () async -> Void = {}
    ) async throws -> URL {
        let ffmpeg = try locateFFmpeg()
        let output = temporaryRemuxURL

        let mapArgs = [
            "-map", "0:v",
            "-map", "0:a:\(audioTrackAIndex)",
            "-map", "0:a:\(audioTrackBIndex)"
        ]
        let common = ["-nostdin", "-loglevel", "error", "-i", source.path]

        let copyArgs = common + mapArgs + ["-c", "copy", "-y", output.path]

        do {
            try await run(executable: ffmpeg, args: copyArgs)
            return output
        } catch let error as MediaPreparationError {
            // Only fall back on a non-zero exit from ffmpeg itself —
            // .ffmpegNotFound or .launchFailed are not recoverable here.
            guard case .remuxFailed = error else { throw error }
            print("[MediaPreparer] copy failed, retrying with re-encode")
            await onReencodeStart()

            let encodeArgs = common + mapArgs + [
                "-c:v", "libx264",
                "-preset", "ultrafast",
                "-crf", "23",
                "-c:a", "aac",
                "-y",
                output.path
            ]
            try await run(executable: ffmpeg, args: encodeArgs)
            return output
        }
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
        print("[MediaPreparer] $ \(executable) \(args.joined(separator: " "))")
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
                    print("[MediaPreparer] launch error: \(error.localizedDescription)")
                    continuation.resume(throwing: MediaPreparationError.launchFailed(error.localizedDescription))
                    return
                }
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let errString = String(data: errData, encoding: .utf8) ?? ""
                let trimmed = errString.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[MediaPreparer] exit=\(process.terminationStatus) stderr=\(trimmed.isEmpty ? "(empty)" : trimmed)")

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: MediaPreparationError.remuxFailed(process.terminationStatus, errString))
                    return
                }
                continuation.resume()
            }
        }
    }
}
