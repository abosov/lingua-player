import SwiftUI

struct SubtitleOverlayView: View {
    let text: String

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
            .background(Color.black.opacity(0.7))
    }
}
