import AsterionKit
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
        case .md: return 8
        case .desktopTile, .hero, .lg: return 10
        }
    }

    /// Point size of the faint mark drawn on a placeholder cover.
    var markSize: CGFloat {
        switch self {
        case .sm:   return 14
        case .md:   return 20
        case .lg:   return 40
        case .tile: return 16
        case .desktopTile: return 26
        case .hero: return 30
        }
    }

    fileprivate var castsShadow: Bool { self == .lg || self == .hero }
}

struct CoverImageView: View {
    @ObserveInjection var inject
    let novel: Novel
    var size: CoverSize = .md

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
    }

    var body: some View {
        Group {
            if let urlString = novel.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        CoverPlaceholder(novel: novel, markSize: size.markSize)
                    default:
                        Color.asterionSurface
                    }
                }
            } else {
                CoverPlaceholder(novel: novel, markSize: size.markSize)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.asterionBorder) }
        .shadow(
            color: .black.opacity(size.castsShadow ? 0.45 : 0),
            radius: size == .lg ? 22 : (size == .hero ? 14 : 0),
            y: size == .lg ? 12 : (size == .hero ? 8 : 0)
        )
        .enableInjection()
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
                    case .failure:
                        CoverPlaceholder(novel: novel, markSize: nil)
                    default:
                        Color.asterionSurface
                    }
                }
            } else {
                CoverPlaceholder(novel: novel, markSize: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// A cover without artwork: the dark surface with the title's initial set
/// faintly in the title-card face, and a quiet genre mark beneath it.
private struct CoverPlaceholder: View {
    let novel: Novel
    /// Fixed mark size for sized covers; `nil` scales with the frame.
    let markSize: CGFloat?

    private var initial: String {
        let letter = novel.title.trimmingCharacters(in: .whitespacesAndNewlines).first
        return letter.map { String($0).uppercased() } ?? ""
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height * 2 / 3)
            let letterSize = markSize.map { $0 * 1.4 } ?? max(14, side * 0.34)
            ZStack {
                Color.asterionSurface
                LinearGradient(
                    colors: [Color.white.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(spacing: letterSize * 0.18) {
                    if !initial.isEmpty {
                        Text(initial)
                            .font(.asterionTitle(letterSize, weight: .heavy))
                            .foregroundStyle(Color.asterionFaint)
                    }
                    if side >= 60 {
                        Image(systemName: GenreStyle.symbol(for: novel.genres))
                            .font(.system(size: max(10, letterSize * 0.32), weight: .light))
                            .foregroundStyle(Color.asterionFaint.opacity(0.7))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}
