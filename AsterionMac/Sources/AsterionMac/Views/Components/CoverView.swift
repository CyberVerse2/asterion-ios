import SwiftUI

struct CoverView: View {
    let novel: Novel
    var width: CGFloat = 150
    var height: CGFloat = 210

    private var genreColor: Color { GenreStyle.color(for: novel.genres) }

    var body: some View {
        AsyncImage(url: novel.imageURL.flatMap(URL.init(string:))) { phase in
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
            Image(systemName: "book.closed.fill")
                .font(.system(size: width * 0.25, weight: .light))
                .foregroundStyle(genreColor.opacity(0.7))
        }
    }
}
