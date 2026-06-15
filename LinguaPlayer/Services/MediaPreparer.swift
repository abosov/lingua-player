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

        print("[Remux] ffmpeg path: \(ffmpeg)")
        print("[Remux] source: \(source.path)")
        print("[Remux] output: \(output.path)")
        print("[Remux] audio A index (0:a:N): \(audioTrackAIndex)")
        print("[Remux] audio B index (0:a:N): \(audioTrackBIndex)")
        // Wipe any prior temp so an empty post-run file is unambiguous.
        try? FileManager.default.removeItem(at: output)

        // We want full ffmpeg output (banner, codec info, warnings) in the
        // log when something fails, so drop -loglevel error from the verbose
        // path. The default verbosity goes to stderr.
        let mapArgs = [
            "-map", "0:v",
            "-map", "0:a:\(audioTrackAIndex)",
            "-map", "0:a:\(audioTrackBIndex)"
        ]
        let common = ["-nostdin", "-i", source.path]

        let copyArgs = common + mapArgs + ["-c", "copy", "-y", output.path]

        do {
            print("[Remux] === attempt: copy ===")
            try await run(executable: ffmpeg, args: copyArgs)
            reportOutputFile(at: output, phase: "copy")
            return output
        } catch let error as MediaPreparationError {
            // Only fall back on a non-zero exit from ffmpeg itself —
            // .ffmpegNotFound or .launchFailed are not recoverable here.
            guard case .remuxFailed = error else { throw error }
            print("[Remux] copy failed, retrying with re-encode")
            reportOutputFile(at: output, phase: "copy (failed)")
            await onReencodeStart()

            let encodeArgs = common + mapArgs + [
                "-c:v", "libx264",
                "-preset", "ultrafast",
                "-crf", "23",
                "-c:a", "aac",
                "-y",
                output.path
            ]
            print("[Remux] === attempt: re-encode ===")
            try await run(executable: ffmpeg, args: encodeArgs)
            reportOutputFile(at: output, phase: "re-encode")
            return output
        }
    }

    private static func reportOutputFile(at url: URL, phase: String) {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: url.path)
        if exists {
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? -1
            print("[Remux] output after \(phase): exists=true size=\(size) bytes path=\(url.path)")
        } else {
            print("[Remux] output after \(phase): MISSING path=\(url.path)")
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
        print("[Remux] $ \(executable) \(args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " "))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    print("[Remux] launch error: \(error.localizedDescription)")
                    continuation.resume(throwing: MediaPreparationError.launchFailed(error.localizedDescription))
                    return
                }
                // Drain both pipes concurrently — if we only read one and the
                // other fills its ~64 KB kernel buffer, ffmpeg blocks.
                let group = DispatchGroup()
                var outData = Data()
                var errData = Data()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    outData = stdout.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.wait()
                process.waitUntilExit()

                let outString = String(data: outData, encoding: .utf8) ?? ""
                let errString = String(data: errData, encoding: .utf8) ?? ""
                let outTrim = outString.trimmingCharacters(in: .whitespacesAndNewlines)
                let errTrim = errString.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[Remux] exit=\(process.terminationStatus)")
                print("[Remux] stdout: \(outTrim.isEmpty ? "(empty)" : "\n\(outTrim)")")
                print("[Remux] stderr: \(errTrim.isEmpty ? "(empty)" : "\n\(errTrim)")")

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: MediaPreparationError.remuxFailed(process.terminationStatus, errString))
                    return
                }
                continuation.resume()
            }
        }
    }
}
