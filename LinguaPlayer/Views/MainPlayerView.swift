import SwiftUI
import AppKit
import AVFoundation

struct MainPlayerView: View {
    @StateObject private var viewModel: PlayerViewModel

    init(setup: PlaybackSetup) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(setup: setup))
    }

    var body: some View {
        VStack(spacing: 0) {
            videoArea
            SubtitleOverlayView(text: viewModel.currentCueText ?? "")
            ControlBarView(viewModel: viewModel)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.black)
        .background(keyboardLayer)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private var videoArea: some View {
        ZStack(alignment: .topTrailing) {
            AVPlayerRepresentable(player: viewModel.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            channelIndicator
                .padding(16)
        }
        .background(Color.black)
    }

    private var channelIndicator: some View {
        Text(viewModel.activeChannel.label)
            .font(.title2.bold())
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(channelColor, in: Circle())
            .shadow(radius: 4)
    }

    private var channelColor: Color {
        switch viewModel.activeChannel {
        case .a: return .blue
        case .b: return .orange
        }
    }

    private var keyboardLayer: some View {
        Group {
            Button("") { viewModel.previousPhrase() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { viewModel.nextPhrase() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { viewModel.toggleChannel() }
                .keyboardShortcut("a", modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}

private struct AVPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerHostView {
        let view = AVPlayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerHostView, context: Context) {
        nsView.playerLayer.player = player
    }
}

final class AVPlayerHostView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Order matters: assigning `layer` before turning on `wantsLayer`
        // makes this a layer-hosting view, which is what AVPlayerLayer needs.
        layer = playerLayer
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }
}
