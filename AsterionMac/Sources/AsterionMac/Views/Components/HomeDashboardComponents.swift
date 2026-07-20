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

    var systemImage: String {
        switch self {
        case .novel: "book.closed"
        case .anime: "play.tv"
        case .movie(let title): title.isSeries ? "tv" : "film"
        }
    }

    var imageURL: URL? {
        switch self {
        case .novel(let novel): novel.imageURL.flatMap(URL.init(string:))
        case .anime(let title): title.imageURL
        case .movie(let title): title.imageURL
        }
    }

    var featureSummary: String {
        switch self {
        case .novel(let novel):
            let summary = novel.summary?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return summary.flatMap { $0.isEmpty ? nil : $0 } ?? "A featured story from Asterion."
        case .anime:
            return "Discover a featured anime from Asterion's latest catalog."
        case .movie(let title):
            return "Explore \(title.displayTitle), featured from Asterion's movie and TV catalog."
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
    @State private var scrollPosition: Item.ID?
    @State private var showsNavigationControls = false
    @State private var hideNavigationControlsTask: Task<Void, Never>?

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
        .scrollPosition(id: $scrollPosition, anchor: .leading)
        .frame(height: height)
        .overlay {
            HStack {
                shelfButton(direction: -1, systemImage: "chevron.left")
                Spacer()
                shelfButton(direction: 1, systemImage: "chevron.right")
            }
            .padding(.horizontal, 8)
            .opacity(showsNavigationControls ? 1 : 0)
            .allowsHitTesting(showsNavigationControls)
        }
        .onScrollPhaseChange { _, phase in
            updateNavigationControls(for: phase)
        }
        .onAppear { scrollPosition = scrollPosition ?? items.first?.id }
        .onDisappear { hideNavigationControlsTask?.cancel() }
        .onChange(of: items.map(\.id)) {
            guard let scrollPosition, items.contains(where: { $0.id == scrollPosition }) else {
                self.scrollPosition = items.first?.id
                return
            }
        }
    }

    private func updateNavigationControls(for phase: ScrollPhase) {
        hideNavigationControlsTask?.cancel()

        guard phase == .idle else {
            withAnimation(.easeOut(duration: 0.16)) {
                showsNavigationControls = true
            }
            return
        }

        hideNavigationControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                showsNavigationControls = false
            }
        }
    }

    private func shelfButton(direction: Int, systemImage: String) -> some View {
        Button {
            let currentIndex = scrollPosition.flatMap { current in
                items.firstIndex(where: { $0.id == current })
            } ?? 0
            let targetIndex = min(max(currentIndex + direction, 0), max(items.count - 1, 0))
            guard items.indices.contains(targetIndex) else { return }
            withAnimation(.snappy) { scrollPosition = items[targetIndex].id }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 48)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .disabled(isShelfEdge(direction: direction))
        .accessibilityLabel(direction < 0 ? "Previous items" : "Next items")
    }

    private func isShelfEdge(direction: Int) -> Bool {
        guard !items.isEmpty else { return true }
        let currentIndex = scrollPosition.flatMap { current in
            items.firstIndex(where: { $0.id == current })
        } ?? 0
        return direction < 0 ? currentIndex == 0 : currentIndex == items.count - 1
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

struct AsterionFeatureCard<Metadata: View, Actions: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isHovering = false

    let imageURL: URL?
    let fallbackSystemImage: String
    let eyebrow: String
    let title: String
    let summary: String
    let previous: (() -> Void)?
    let next: (() -> Void)?
    @ViewBuilder let metadata: () -> Metadata
    @ViewBuilder let actions: () -> Actions

    init(
        imageURL: URL?,
        fallbackSystemImage: String,
        eyebrow: String,
        title: String,
        summary: String,
        previous: (() -> Void)? = nil,
        next: (() -> Void)? = nil,
        @ViewBuilder metadata: @escaping () -> Metadata,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.imageURL = imageURL
        self.fallbackSystemImage = fallbackSystemImage
        self.eyebrow = eyebrow
        self.title = title
        self.summary = summary
        self.previous = previous
        self.next = next
        self.metadata = metadata
        self.actions = actions
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backdrop
                LinearGradient(
                    colors: [.black.opacity(0.90), .black.opacity(0.24)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 0) {
                    poster

                    VStack(alignment: .leading, spacing: 8) {
                        Text(eyebrow)
                            .font(.asterionMono(10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(Color.asterionAccent)

                        Text(title)
                            .font(.asterionDisplay(23, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        metadata()

                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.76))
                            .lineSpacing(2)
                            .lineLimit(2)
                            .padding(.top, 3)
                            .accessibilityLabel("Synopsis")
                            .accessibilityValue(summary)

                        Spacer(minLength: 6)

                        HStack(spacing: 10) {
                            actions()
                            Spacer()
                            if let previous, let next {
                                navigationButton(
                                    systemImage: "chevron.left",
                                    help: "Previous featured item",
                                    action: previous
                                )
                                navigationButton(
                                    systemImage: "chevron.right",
                                    help: "Next featured item",
                                    action: next
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 9)
        .onHover { isHovering = $0 }
        .task(id: title) {
            guard next != nil, !reduceMotion else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(8))
                } catch {
                    return
                }
                guard scenePhase == .active, !isHovering else { continue }
                next?()
            }
        }
    }

    private var backdrop: some View {
        AsyncImage(url: imageURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill().blur(radius: 24).scaleEffect(1.18)
            } else {
                Color.asterionCard
            }
        }
        .clipped()
    }

    private var poster: some View {
        AsyncImage(url: imageURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Color.asterionCard.overlay {
                    Image(systemName: fallbackSystemImage)
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Color.asterionAccent.opacity(0.72))
                }
            }
        }
        .frame(width: 156, height: 220)
        .clipped()
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.34)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 30)
        }
        .accessibilityHidden(true)
    }

    private func navigationButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.70))
        .help(help)
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
