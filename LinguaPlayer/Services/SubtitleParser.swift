import Foundation

enum SubtitleParseError: LocalizedError {
    case ffmpegNotFound
    case extractionFailed(Int32, String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "ffmpeg not found. Install via Homebrew: brew install ffmpeg"
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
/// Requires ffmpeg on the host (Homebrew or system). The app must run
/// unsandboxed so Process can launch /opt/homebrew/bin/ffmpeg etc.
enum SubtitleParser {
    static func extractCues(fileURL: URL, subtitleStreamIndex: Int) async throws -> [SubtitleCue] {
        let ffmpeg = try findFFmpeg()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
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

        let srt: String = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                guard proc.terminationStatus == 0 else {
                    let msg = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: SubtitleParseError.extractionFailed(proc.terminationStatus, msg))
                    return
                }
                guard let text = String(data: outData, encoding: .utf8) else {
                    continuation.resume(throwing: SubtitleParseError.decodingFailed)
                    return
                }
                continuation.resume(returning: text)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        return parseSRT(srt)
    }

    private static func findFFmpeg() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw SubtitleParseError.ffmpegNotFound
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
            cues.append(SubtitleCue(id: index, startTime: start, endTime: end, text: text))
        }
        return cues
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
