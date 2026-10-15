import Inject
import SwiftUI

enum CoverSize {
    case sm, md, lg, tile, desktopTile, hero

    var width: CGFloat {
        switch self {
        case .sm:   return 44
        case .md:   return 72
        case .lg:   return 140
        case .tile: return 48
        case .desktopTile: return 92
        case .hero: return 104
        }
    }

    var height: CGFloat {
        switch self {
        case .sm:   return 60
        case .md:   return 108
        case .lg:   return 190
        case .tile: return 64
        case .desktopTile: return 124
        case .hero: return 148
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .sm, .tile: return 6
        case .md: return 12
        case .desktopTile, .hero: return 10
        case .lg:             return 12
        }
    }

    var emojiSize: CGFloat {
        switch self {
        case .sm:   return 20
        case .md:   return 24
        case .lg:   return 56
        case .tile: return 22
        case .desktopTile: return 34
        case .hero: return 40
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
        .shadow(
            color: (size == .lg || size == .hero) ? genreColor.opacity(0.22) : .clear,
            radius: size == .lg ? 30 : (size == .hero ? 18 : 0),
            y: size == .lg ? 20 : (size == .hero ? 10 : 0)
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

struct NovelPosterArt: View {
    let novel: Novel

    var body: some View {
        Group {
            if let urlString = novel.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var fallback: some View {
        Color.asterionCard
            .overlay {
                Text(String(novel.title.prefix(1)))
                    .font(.asterionDisplay(44, weight: .medium))
                    .foregroundStyle(Color.asterionText)
            }
    }
}
