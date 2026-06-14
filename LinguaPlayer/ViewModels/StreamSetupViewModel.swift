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
              let sIndex = subtitleTracks.firstIndex(where: { $0.id == s })
        else { return }
        print("[StreamSetupViewModel] continue — audio A:#\(aIndex), audio B:#\(bIndex), subtitle:#\(sIndex)")
        Task { await prepare(source: url, audioA: aIndex, audioB: bIndex, subtitle: sIndex) }
    }

    private func prepare(source: URL, audioA: Int, audioB: Int, subtitle: Int) async {
        isPreparing = true
        preparingStatus = "Preparing video…"
        errorMessage = nil
        defer {
            isPreparing = false
            preparingStatus = nil
        }

        do {
            async let remuxedTask = MediaPreparer.remux(
                source: source,
                audioTrackAIndex: audioA,
                audioTrackBIndex: audioB
            )
            async let cuesTask = SubtitleParser.extractCues(
                fileURL: source,
                subtitleStreamIndex: subtitle
            )
            let (remuxedURL, cues) = try await (remuxedTask, cuesTask)
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
            subtitleTracks = tracks.filter { $0.kind == .subtitle }
            if tracks.isEmpty {
                errorMessage = VideoProbeError.noTracksFound.errorDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
