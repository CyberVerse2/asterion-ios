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
                    .font(.asterionDisplay(24, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            .padding(.leading, 24)
            content()
        }
    }
}

struct HomePagedShelf<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let itemWidth: CGFloat
    let spacing: CGFloat
    let height: CGFloat
    @ViewBuilder let card: (Item) -> Card

    @State private var firstVisibleIndex = 0

    var body: some View {
        GeometryReader { geometry in
            let visibleCount = max(
                1,
                Int((geometry.size.width + spacing) / (itemWidth + spacing))
            )
            let maximumIndex = max(0, items.count - visibleCount)
            let currentIndex = min(firstVisibleIndex, maximumIndex)

            ZStack {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        card(item)
                    }
                }
                .frame(height: height, alignment: .top)
                .offset(x: -CGFloat(currentIndex) * (itemWidth + spacing))
                .frame(maxWidth: .infinity, alignment: .leading)

                if currentIndex > 0 {
                    shelfButton(systemImage: "chevron.left") {
                        move(
                            to: max(0, currentIndex - max(1, visibleCount - 1))
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                }

                if currentIndex < maximumIndex {
                    shelfButton(systemImage: "chevron.right") {
                        move(
                            to: min(
                                maximumIndex,
                                currentIndex + max(1, visibleCount - 1)
                            )
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                }
            }
            .clipped()
            .onChange(of: items.count) {
                firstVisibleIndex = min(firstVisibleIndex, maximumIndex)
            }
        }
        .frame(height: height)
    }

    private func move(to index: Int) {
        withAnimation(.snappy(duration: 0.28)) {
            firstVisibleIndex = index
        }
    }

    private func shelfButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(systemImage == "chevron.left" ? "Previous titles" : "More titles")
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
                .frame(maxWidth: 620, alignment: .leading)

                Spacer(minLength: 20)
                MediaCoverView(url: item.imageURL, width: 142, height: 202)
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                    .accessibilityHidden(true)
            }
            .padding(26)
        }
        .frame(maxWidth: .infinity, minHeight: 272, maxHeight: 272)
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
                    .stroke(.white.opacity(0.10))
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
                .frame(width: 190, height: 270)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.12), .black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.badge)
                        .font(.asterionMono(8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())

                    Text(item.title)
                        .font(.asterionDisplay(17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                }
                .padding(14)
            }
            .frame(width: 190, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.white.opacity(0.10))
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
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
                    .stroke(.white.opacity(0.10))
            }
        }
        .buttonStyle(.plain)
        .asterionHoverLift()
        .help("Open \(match.displayTitle)")
    }
}
