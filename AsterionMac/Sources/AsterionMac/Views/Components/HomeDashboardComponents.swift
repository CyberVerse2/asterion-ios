import SwiftUI

enum HomeResumeItem: Identifiable {
    case reading(AppModel.ContinueReadingEntry)
    case watching(MediaPlaybackProgress)

    var id: String {
        switch self {
        case .reading(let entry): "reading:\(entry.id)"
        case .watching(let progress): "watching:\(progress.id)"
        }
    }

    var title: String {
        switch self {
        case .reading(let entry): entry.novel.title
        case .watching(let progress): progress.title
        }
    }

    var subtitle: String {
        switch self {
        case .reading:
            return "Continue reading"
        case .watching(let progress):
            let unitTitle = progress.unitTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let numberedUnit: String? = if let season = progress.seasonNumber,
                                           let episode = progress.episodeNumber {
                "S\(season) E\(episode)"
            } else if let episode = progress.episodeNumber {
                "Episode \(episode)"
            } else {
                nil
            }

            if let numberedUnit, let unitTitle, !unitTitle.isEmpty,
               !unitTitle.lowercased().hasPrefix("episode "),
               !unitTitle.localizedCaseInsensitiveContains(numberedUnit) {
                return "\(numberedUnit) · \(unitTitle)"
            } else {
                return numberedUnit ?? unitTitle ?? progress.mediaType.title
            }
        }
    }

    var kindTitle: String {
        switch self {
        case .reading: "Novel"
        case .watching(let progress): progress.mediaType == .anime ? "Anime" : "Movie & TV"
        }
    }

    var systemImage: String {
        switch self {
        case .reading: "book.fill"
        case .watching: "play.fill"
        }
    }

    var imageURL: URL? {
        switch self {
        case .reading(let entry): entry.novel.imageURL.flatMap(URL.init(string:))
        case .watching(let progress): progress.imageURL
        }
    }

    var percentage: Double {
        switch self {
        case .reading(let entry): entry.progress.percentage
        case .watching(let progress): progress.percentage
        }
    }

    var updatedAt: Date {
        switch self {
        case .reading(let entry): entry.progress.updatedAt ?? .distantPast
        case .watching(let progress): progress.updatedAt
        }
    }
}

enum HomeCatalogItem: Identifiable {
    case novel(Novel)
    case anime(AnimeTitle)
    case movie(MovieTitle)

    var id: String {
        switch self {
        case .novel(let novel): "novel:\(novel.id)"
        case .anime(let title): "anime:\(title.id)"
        case .movie(let title): "movie:\(title.id)"
        }
    }

    var title: String {
        switch self {
        case .novel(let novel): novel.title
        case .anime(let title): title.displayTitle
        case .movie(let title): title.displayTitle
        }
    }

    var subtitle: String {
        switch self {
        case .novel(let novel): novel.authorDisplayName
        case .anime(let title): title.episodeLabel ?? title.type ?? "Anime"
        case .movie(let title): [title.isSeries ? "TV Series" : "Movie", title.year]
                .compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    var kindTitle: String {
        switch self {
        case .novel: "Novels"
        case .anime: "Anime"
        case .movie(let title): title.isSeries ? "TV Shows" : "Movies"
        }
    }

    var badge: String {
        switch self {
        case .novel: "NOVEL"
        case .anime: "ANIME"
        case .movie(let title): title.isSeries ? "SERIES" : "MOVIE"
        }
    }

    var imageURL: URL? {
        switch self {
        case .novel(let novel): novel.imageURL.flatMap(URL.init(string:))
        case .anime(let title): title.imageURL
        case .movie(let title): title.imageURL
        }
    }
}

struct HomeSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            .padding(.leading, 32)
            content()
        }
    }
}

struct HomeHorizontalShelf<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let itemWidth: CGFloat
    let spacing: CGFloat
    let height: CGFloat
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: spacing) {
                ForEach(items) { item in
                    card(item)
                        .frame(width: itemWidth)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 32, for: .scrollContent)
        .scrollIndicators(.never, axes: .horizontal)
        .scrollTargetBehavior(.viewAligned)
        .frame(height: height)
    }
}

struct HomeContinueCard: View {
    let item: HomeResumeItem
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: item.imageURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.asterionCard
                    }
                }
                .frame(width: 294, height: 166)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.22), .black.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.asterionDisplay(18, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: item.systemImage)
                            .font(.caption.weight(.bold))
                        Text(item.subtitle)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(Int(item.percentage.rounded()))%")
                            .monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))

                    ProgressView(value: min(100, max(0, item.percentage)), total: 100)
                        .tint(Color.asterionAccent)
                }
                .padding(14)
            }
            .frame(width: 294, height: 166)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.asterionAccent : .white.opacity(0.10),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .help("Resume \(item.title)")
    }
}

struct HomePosterCard: View {
    let item: HomeCatalogItem
    let action: () -> Void

    var body: some View {
        AsterionPosterCard(
            imageURL: item.imageURL,
            badge: item.badge,
            title: item.title,
            subtitle: item.subtitle,
            action: action
        )
    }
}

struct AsterionPosterCard: View {
    let imageURL: URL?
    let badge: String
    let title: String
    let subtitle: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: imageURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.asterionCard
                    }
                }
                .frame(width: 168, height: 252)
                .clipped()

                LinearGradient(
                    colors: [.clear, .clear, .black.opacity(0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(badge)
                        .font(.asterionMono(7, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())

                    Text(title)
                        .font(.asterionDisplay(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(12)
            }
            .frame(width: 168, height: 252)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.asterionAccent : .white.opacity(0.10),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .help("Open \(title)")
        .accessibilityLabel("\(title), \(badge)")
    }
}

struct HomeMatchCard: View {
    let match: FootballMatch
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: match.posterURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.asterionCard
                    }
                }
                .frame(width: 330, height: 174)
                .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.08), .black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                HStack(spacing: 12) {
                    FootballBadgeView(team: match.homeTeam, size: 38)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(match.isLive ? "LIVE" : match.kickoff.formatted(date: .omitted, time: .shortened))
                                .font(.asterionMono(9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(match.isLive ? Color.asterionAccent : .white.opacity(0.72))
                            Text(match.category)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)
                        }
                        Text(match.displayTitle)
                            .font(.asterionDisplay(17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)
                    FootballBadgeView(team: match.awayTeam, size: 38)
                }
                .padding(16)
            }
            .frame(width: 330, height: 174)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.asterionAccent : .white.opacity(0.10),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .help("Open \(match.displayTitle)")
    }
}
