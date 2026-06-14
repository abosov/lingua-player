import SwiftUI

struct StreamSetupView: View {
    @StateObject private var viewModel = StreamSetupViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack {
                Button("Open Video…") {
                    viewModel.openFile()
                }
                .controlSize(.large)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(viewModel.isLoading)

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Probing tracks…")
                        .foregroundStyle(.secondary)
                }
            }

            if let url = viewModel.fileURL {
                Text(url.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if !viewModel.audioTracks.isEmpty || !viewModel.subtitleTracks.isEmpty {
                tracksList
            } else {
                Spacer()
                placeholder
                Spacer()
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lingua Player")
                .font(.largeTitle.bold())
            Text("Open a video file to inspect its audio and subtitle tracks.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var placeholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text("No file loaded")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var tracksList: some View {
        List {
            Section("Audio Tracks (\(viewModel.audioTracks.count))") {
                if viewModel.audioTracks.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.audioTracks) { track in
                        TrackRow(track: track)
                    }
                }
            }

            Section("Subtitle Tracks (\(viewModel.subtitleTracks.count))") {
                if viewModel.subtitleTracks.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.subtitleTracks) { track in
                        TrackRow(track: track)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

private struct TrackRow: View {
    let track: MediaTrack

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("#\(track.id)")
                .monospaced()
                .frame(width: 48, alignment: .leading)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.language ?? "Unknown language")
                    .font(.body)

                HStack(spacing: 8) {
                    if let codec = track.codec {
                        Label(codec, systemImage: "waveform")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let description = track.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    StreamSetupView()
}
