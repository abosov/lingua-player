import SwiftUI

struct SubtitleOverlayView: View {
    let text: String
    let isVisible: Bool

    // Fixed bar height keeps the video area from resizing as cues come and
    // go. Long lines truncate rather than expand the bar.
    private static let barHeight: CGFloat = 80

    var body: some View {
        Group {
            if isVisible {
                Text(text)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 24)
            } else {
                Label("Subtitles off", systemImage: "captions.bubble")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .frame(height: Self.barHeight)
        .background(Color.black)
    }
}
