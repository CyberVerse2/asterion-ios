import SwiftUI

struct MediaCoverView: View {
    let url: URL?
    var width: CGFloat = 150
    var height: CGFloat = 210

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty:
                fallback.overlay { ProgressView().controlSize(.small) }
            case .failure:
                fallback
            @unknown default:
                fallback
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: max(6, width * 0.06), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(6, width * 0.06), style: .continuous)
                .stroke(Color.asterionBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: width * 0.08, y: width * 0.035)
    }

    private var fallback: some View {
        Color.asterionCard
            .overlay {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: width * 0.25, weight: .light))
                    .foregroundStyle(Color.asterionAccent.opacity(0.7))
            }
    }
}
