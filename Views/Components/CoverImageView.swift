import Inject
import SwiftUI

enum CoverSize {
    case sm, md, lg, tile

    var width: CGFloat {
        switch self {
        case .sm:   return 44
        case .md:   return 52
        case .lg:   return 140
        case .tile: return 48
        }
    }

    var height: CGFloat {
        switch self {
        case .sm:   return 60
        case .md:   return 70
        case .lg:   return 190
        case .tile: return 64
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .sm, .md, .tile: return 6
        case .lg:             return 12
        }
    }

    var emojiSize: CGFloat {
        switch self {
        case .sm:   return 20
        case .md:   return 24
        case .lg:   return 56
        case .tile: return 22
        }
    }
}

struct CoverImageView: View {
    @ObserveInjection var inject
    let novel: Novel
    var size: CoverSize = .md

    private var genreColor: Color { GenreStyle.color(for: novel.genres) }
    private var genreEmoji: String { GenreStyle.emoji(for: novel.genres) }

    var body: some View {
        Group {
            if let urlString = novel.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        fallbackView
                    default:
                        fallbackView.overlay {
                            ProgressView()
                                .tint(genreColor)
                                .scaleEffect(0.5)
                        }
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .stroke(genreColor.opacity(size == .lg ? 0.3 : 0.15), lineWidth: 1)
        )
        .shadow(
            color: size == .lg ? genreColor.opacity(0.2) : .clear,
            radius: size == .lg ? 30 : 0,
            y: size == .lg ? 20 : 0
        )
        .enableInjection()
    }

    private var fallbackView: some View {
        RoundedRectangle(cornerRadius: size.cornerRadius)
            .fill(
                LinearGradient(
                    colors: [genreColor.opacity(0.3), genreColor.opacity(size == .lg ? 0.2 : 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Text(genreEmoji)
                    .font(.system(size: size.emojiSize))
            }
    }
}
