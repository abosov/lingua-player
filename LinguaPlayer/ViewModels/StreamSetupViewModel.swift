import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class StreamSetupViewModel: ObservableObject {
    @Published private(set) var fileURL: URL?
    @Published private(set) var audioTracks: [MediaTrack] = []
    @Published private(set) var subtitleTracks: [MediaTrack] = []
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published private(set) var channelA: Int?
    @Published private(set) var channelB: Int?
    @Published private(set) var activeSubtitle: Int?
    @Published private(set) var playbackSetup: PlaybackSetup?

    @Published private(set) var isPreparing: Bool = false
    @Published private(set) var preparingStatus: String?

    private let engine: VideoPlayerEngine

    init(engine: VideoPlayerEngine = VideoPlayerEngine()) {
        self.engine = engine
    }

    var canContinue: Bool {
        channelA != nil && channelB != nil && activeSubtitle != nil
    }

    func channel(for trackId: Int) -> Channel? {
        if channelA == trackId { return .a }
        if channelB == trackId { return .b }
        return nil
    }

    func isActiveSubtitle(_ trackId: Int) -> Bool {
        activeSubtitle == trackId
    }

    func toggleAssignment(for trackId: Int) {
        if channelA == trackId {
            channelA = nil
        } else if channelB == trackId {
            channelB = nil
        } else if channelA == nil {
            channelA = trackId
        } else if channelB == nil {
            channelB = trackId
        }
    }

    func toggleSubtitle(for trackId: Int) {
        if activeSubtitle == trackId {
            activeSubtitle = nil
        } else {
            activeSubtitle = trackId
        }
    }

    func continueToPlayer() {
        guard !isPreparing,
              let url = fileURL,
              let a = channelA, let b = channelB, let s = activeSubtitle,
              let aIndex = audioTracks.firstIndex(where: { $0.id == a }),
              let bIndex = audioTracks.firstIndex(where: { $0.id == b }),
              let subtitleTrack = subtitleTracks.first(where: { $0.id == s })
        else { return }
        print("[StreamSetupViewModel] continue — audio A:#\(aIndex), audio B:#\(bIndex), subtitle:\(subtitleTrack.isExternal ? "external" : "embedded") \(subtitleTrack.description ?? "")")
        Task { await prepare(source: url, audioA: aIndex, audioB: bIndex, subtitle: subtitleTrack) }
    }

    private func prepare(source: URL, audioA: Int, audioB: Int, subtitle: MediaTrack) async {
        isPreparing = true
        preparingStatus = "Preparing video…"
        errorMessage = nil
        defer {
            isPreparing = false
            preparingStatus = nil
        }

        // Snapshot what the cue task needs up front — once the Task starts it
        // runs off the main actor and can't touch @MainActor state.
        let externalURL = subtitle.externalURL
        // ffmpeg's `0:s:N` selector counts subtitle streams in their file
        // order — match that by filtering out the external tracks we
        // appended ourselves.
        let embeddedIndex: Int? = subtitleTracks
            .filter { !$0.isExternal }
            .firstIndex(where: { $0.id == subtitle.id })

        do {
            let remuxTask = Task {
                try await MediaPreparer.remux(
                    source: source,
                    audioTrackAIndex: audioA,
                    audioTrackBIndex: audioB,
                    onReencodeStart: { @MainActor [weak self] in
                        self?.preparingStatus = "Converting video…"
                    }
                )
            }
            let cuesTask = Task { () throws -> [SubtitleCue] in
                if let externalURL {
                    return try await SubtitleParser.parseFile(at: externalURL)
                }
                guard let embeddedIndex else { return [] }
                return try await SubtitleParser.extractCues(
                    fileURL: source,
                    subtitleStreamIndex: embeddedIndex
                )
            }
            let remuxedURL = try await remuxTask.value
            let cues = try await cuesTask.value
            playbackSetup = PlaybackSetup(remuxedURL: remuxedURL, cues: cues)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.message = "Select a video file"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.allowedTypes

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await probe(url: url) }
    }

    private static var allowedTypes: [UTType] {
        var types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        for ext in ["mkv", "avi", "mp4", "mov", "m4v"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    private func probe(url: URL) async {
        fileURL = url
        audioTracks = []
        subtitleTracks = []
        channelA = nil
        channelB = nil
        activeSubtitle = nil
        playbackSetup = nil
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let tracks = try await engine.probeTracks(at: url)
            audioTracks = tracks.filter { $0.kind == .audio }
            let embeddedSubs = tracks.filter { $0.kind == .subtitle }
            let nextId = (tracks.map(\.id).max() ?? -1) + 1
            subtitleTracks = embeddedSubs + Self.discoverExternalSubtitles(for: url, startingId: nextId)
            if tracks.isEmpty {
                errorMessage = VideoProbeError.noTracksFound.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Looks for sidecar .srt files in the video's folder whose stem starts
    /// with the video's stem — e.g. for "Movie_2022.avi" we accept
    /// "Movie_2022.srt", "Movie_2022_eng.srt", "Movie_2022 rus forced.srt".
    /// Match is case-insensitive to play well with HFS+/APFS defaults.
    private static func discoverExternalSubtitles(for url: URL, startingId: Int) -> [MediaTrack] {
        let baseName = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let prefix = baseName.lowercased()
        let suffixTrim = CharacterSet(charactersIn: " _-.")
        return entries
            .filter { $0.pathExtension.lowercased() == "srt" }
            .filter { $0.deletingPathExtension().lastPathComponent.lowercased().hasPrefix(prefix) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .enumerated()
            .map { offset, srtURL in
                let stem = srtURL.deletingPathExtension().lastPathComponent
                let rawSuffix = String(stem.dropFirst(baseName.count))
                let label = rawSuffix.trimmingCharacters(in: suffixTrim)
                return MediaTrack(
                    id: startingId + offset,
                    kind: .subtitle,
                    source: .external(srtURL),
                    language: label.isEmpty ? "External" : label,
                    codec: "SRT",
                    description: srtURL.lastPathComponent
                )
            }
    }
}
