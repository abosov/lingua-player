import SwiftUI

struct SubtitleOverlayView: View {
    let text: String

    // Fixed bar height keeps the video area from resizing as cues come and
    // go. Long lines truncate rather than expand the bar.
    private static let barHeight: CGFloat = 80

    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .frame(height: Self.barHeight)
            .background(Color.black)
    }
}
