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
    let subtitle: String
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.asterionDisplay(22, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Color.asterionMuted)
            }
            content()
        }
    }
}

struct ResumeSpotlight: View {
    let item: HomeResumeItem
    let action: () -> Void

    var body: some View {
        ZStack {
            AsyncImage(url: item.imageURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill().blur(radius: 28).scaleEffect(1.18)
                } else {
                    Color.asterionCard
                }
            }
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.92), .black.opacity(0.38)],
                startPoint: .leading,
                endPoint: .trailing
            )

            HStack(spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PICK UP WHERE YOU LEFT OFF")
                        .font(.asterionMono(10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Color.asterionAccent)
                    Text(item.title)
                        .font(.asterionDisplay(28, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Label(item.subtitle, systemImage: item.systemImage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))

                    HStack(spacing: 10) {
                        ProgressView(value: min(100, max(0, item.percentage)), total: 100)
                            .tint(Color.asterionAccent)
                            .frame(maxWidth: 360)
                        Text("\(Int(item.percentage.rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Button(action: action) {
                        Label(item.kindTitle == "Novel" ? "Continue reading" : "Continue watching", systemImage: item.systemImage)
                            .font(.headline)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.asterionAccent)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MediaCoverView(url: item.imageURL, width: 142, height: 202)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                    .accessibilityHidden(true)
            }
            .padding(26)
        }
        .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 250)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resume \(item.title), \(Int(item.percentage.rounded())) percent complete")
    }
}

struct HomeContinueCard: View {
    let item: HomeResumeItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                MediaCoverView(url: item.imageURL, width: 108, height: 154)
                Text(item.title)
                    .font(.asterionDisplay(14, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .frame(width: 116, alignment: .leading)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                    .frame(width: 116, alignment: .leading)
                Text(item.kindTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.asterionAccent)
                    .lineLimit(1)
                ProgressView(value: min(100, max(0, item.percentage)), total: 100)
                    .tint(Color.asterionAccent)
                    .frame(width: 116)
            }
            .contentShape(Rectangle())
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
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    MediaCoverView(url: item.imageURL, width: 118, height: 168)
                    Text(item.badge)
                        .font(.asterionMono(8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.asterionAccent, in: Capsule())
                        .padding(7)
                }
                Text(item.title)
                    .font(.asterionDisplay(14, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .frame(width: 126, alignment: .leading)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                    .frame(width: 126, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .help("Open \(item.title)")
        .accessibilityLabel("\(item.title), \(item.badge)")
    }
}

struct HomeMatchCard: View {
    let match: FootballMatch
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                FootballBadgeView(team: match.homeTeam, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(match.isLive ? "LIVE" : match.kickoff.formatted(date: .omitted, time: .shortened))
                            .font(.asterionMono(9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(match.isLive ? Color.asterionAccent : Color.asterionMuted)
                        Text(match.category)
                            .font(.caption2)
                            .foregroundStyle(Color.asterionMuted)
                            .lineLimit(1)
                    }
                    Text(match.displayTitle)
                        .font(.asterionDisplay(15, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                        .lineLimit(1)
                }
                Spacer(minLength: 10)
                FootballBadgeView(team: match.awayTeam, size: 34)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.asterionMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(width: 360, alignment: .leading)
            .background(Color.asterionCard, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(.white.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .help("Open \(match.displayTitle)")
    }
}

struct HomeMetricCard: View {
    let value: Int
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.asterionAccent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value, format: .number)
                        .font(.asterionDisplay(22, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(Color.asterionMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.asterionMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.asterionCard, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(.white.opacity(0.08))
            }
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .accessibilityLabel("\(value) \(label)")
    }
}
