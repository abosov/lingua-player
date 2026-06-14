import Foundation

enum SubtitleParseError: LocalizedError {
    case ffmpegNotFound
    case launchFailed(String)
    case extractionFailed(Int32, String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found at /usr/local/bin/ffmpeg or /opt/homebrew/bin/ffmpeg. Install via Homebrew: brew install ffmpeg"
        case .launchFailed(let msg):
            return "Could not launch ffmpeg: \(msg)"
        case .extractionFailed(let code, let stderr):
            let snippet = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "ffmpeg failed (exit \(code))" + (snippet.isEmpty ? "" : ": \(snippet)")
        case .decodingFailed:
            return "Could not decode SRT output from ffmpeg."
        }
    }
}

/// Extracts a single embedded subtitle track from a media file by shelling
/// out to ffmpeg ("-f srt pipe:1") and parsing the resulting SRT.
///
/// The app must run unsandboxed so Process can launch /usr/local/bin/ffmpeg
/// or /opt/homebrew/bin/ffmpeg. We use absolute paths because GUI apps
/// launched from Xcode/Finder inherit a minimal PATH that does not include
/// Homebrew locations.
enum SubtitleParser {
    private static let ffmpegCandidates = [
        "/usr/local/bin/ffmpeg",      // Intel Homebrew, MacPorts
        "/opt/homebrew/bin/ffmpeg"    // Apple Silicon Homebrew
    ]

    static func extractCues(fileURL: URL, subtitleStreamIndex: Int) async throws -> [SubtitleCue] {
        let ffmpeg = try locateFFmpeg()
        let srt = try await runFFmpeg(executable: ffmpeg, fileURL: fileURL, subtitleStreamIndex: subtitleStreamIndex)
        return parseSRT(srt)
    }

    /// Reads an external .srt file from disk and parses it. SRTs in the wild
    /// come in mixed encodings — UTF-8 first, then CP1251 (common for Russian
    /// fansubs), then Latin-1 as a last resort.
    static func parseFile(at url: URL) async throws -> [SubtitleCue] {
        let data = try Data(contentsOf: url)
        let candidates: [String.Encoding] = [.utf8, .windowsCP1251, .isoLatin1]
        for encoding in candidates {
            if let text = String(data: data, encoding: encoding) {
                return parseSRT(text)
            }
        }
        throw SubtitleParseError.decodingFailed
    }

    private static func locateFFmpeg() throws -> String {
        for path in ffmpegCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw SubtitleParseError.ffmpegNotFound
    }

    private static func runFFmpeg(
        executable: String,
        fileURL: URL,
        subtitleStreamIndex: Int
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "-nostdin",
            "-loglevel", "error",
            "-i", fileURL.path,
            "-map", "0:s:\(subtitleStreamIndex)",
            "-f", "srt",
            "pipe:1"
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withCheckedThrowingContinuation { continuation in
            // Drain stdout + stderr concurrently in background threads. If we
            // only read after termination, ffmpeg blocks once the kernel pipe
            // buffer (~64 KB) fills — which it will for any non-trivial SRT.
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: SubtitleParseError.launchFailed(error.localizedDescription))
                    return
                }

                let buffers = IOBuffers()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    buffers.out = stdout.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    buffers.err = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.wait()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    let msg = String(data: buffers.err, encoding: .utf8) ?? ""
                    continuation.resume(throwing: SubtitleParseError.extractionFailed(process.terminationStatus, msg))
                    return
                }
                guard let text = String(data: buffers.out, encoding: .utf8) else {
                    continuation.resume(throwing: SubtitleParseError.decodingFailed)
                    return
                }
                continuation.resume(returning: text)
            }
        }
    }

    private static func parseSRT(_ raw: String) -> [SubtitleCue] {
        let cleaned = raw
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var cues: [SubtitleCue] = []
        let blocks = cleaned.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }

            var cursor = 0
            var index = cues.count + 1
            if let parsedIndex = Int(lines[cursor].trimmingCharacters(in: .whitespaces)) {
                index = parsedIndex
                cursor += 1
            }
            guard cursor < lines.count else { continue }
            guard let (start, end) = parseTimecodes(lines[cursor]) else { continue }
            cursor += 1
            guard cursor < lines.count else { continue }

            let text = lines[cursor...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            cues.append(SubtitleCue(id: index, startTime: start, endTime: end, text: stripTags(text)))
        }
        return cues
    }

    private static let tagRegex = try! NSRegularExpression(pattern: "<[^>]+>")

    private static func stripTags(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        let stripped = tagRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseTimecodes(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: " --> ")
        guard parts.count == 2 else { return nil }
        guard let start = parseTimestamp(parts[0]),
              let end = parseTimestamp(parts[1]) else { return nil }
        return (start, end)
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        // HH:MM:SS,mmm  or  HH:MM:SS.mmm
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}

/// Two-field box for the concurrent pipe readers. Writes to distinct fields
/// happen on separate queues; DispatchGroup gives the happens-before barrier.
private final class IOBuffers: @unchecked Sendable {
    var out = Data()
    var err = Data()
}
