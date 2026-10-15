import SwiftUI

struct MediaCoverView: View {
    let url: URL?
    var width: CGFloat = 150
    var height: CGFloat = 210

    private var cornerRadius: CGFloat { max(6, min(10, width * 0.06)) }

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty:
                loadingFallback
            case .failure:
                fallback
            @unknown default:
                fallback
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.asterionBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.28), radius: width * 0.08, y: width * 0.035)
    }

    private var fallback: some View {
        Color.asterionSurface
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.system(size: max(12, width * 0.2), weight: .light))
                    .foregroundStyle(Color.asterionFaint)
            }
    }

    private var loadingFallback: some View {
        Color.asterionSurface
            .accessibilityLabel("Loading cover artwork")
    }
}
