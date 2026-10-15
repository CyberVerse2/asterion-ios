import SwiftUI

enum AsterionCardMetrics {
    static let posterWidth: CGFloat = 156
    static let posterHeight: CGFloat = 234
    /// Poster art plus the two caption lines set beneath it.
    static let posterShelfHeight: CGFloat = 290
    static let landscapeWidth: CGFloat = 300
    static let landscapeHeight: CGFloat = 169
    static let landscapeShelfHeight: CGFloat = 178
    static let matchWidth: CGFloat = 320
    static let matchHeight: CGFloat = 168
    static let matchShelfHeight: CGFloat = 176
    static let episodeWidth: CGFloat = 220
    static let episodeHeight: CGFloat = 124
}

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
        case .novel: "Novel"
        case .anime: "Anime"
        case .movie(let title): title.isSeries ? "Series" : "Film"
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

    var featureSummary: String? {
        switch self {
        case .novel(let novel):
            let summary = novel.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.flatMap { $0.isEmpty ? nil : $0 }
        case .anime, .movie:
            return nil
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .novel: "View novel"
        case .anime: "View anime"
        case .movie(let title): title.isSeries ? "View series" : "View film"
        }
    }
}

// MARK: - Shelves

struct HomeSection<Content: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.asterionTitle(18, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, AsterionLayout.pageInset)
            content()
        }
    }
}

struct HomeHorizontalShelf<Item: Identifiable, Card: View>: View {
    @State private var scrollPosition: Item.ID?
    @State private var isHovering = false
    @State private var availableWidth: CGFloat = 1_100

    let items: [Item]
    let itemWidth: CGFloat
    let spacing: CGFloat
    let height: CGFloat
    @ViewBuilder let card: (Item) -> Card

    private var cardScale: CGFloat {
        min(1, max(0.84, availableWidth / 1_100))
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: spacing * cardScale) {
                ForEach(items) { item in
                    card(item)
                        .frame(width: itemWidth)
                        .scaleEffect(cardScale, anchor: .topLeading)
                        .frame(
                            width: itemWidth * cardScale,
                            height: height * cardScale,
                            alignment: .topLeading
                        )
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, AsterionLayout.pageInset, for: .scrollContent)
        .scrollIndicators(.never, axes: .horizontal)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollPosition, anchor: .leading)
        .frame(height: height * cardScale)
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
        .overlay {
            HStack {
                shelfButton(direction: -1, systemImage: "chevron.left")
                Spacer()
                shelfButton(direction: 1, systemImage: "chevron.right")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 40 * cardScale)
            .opacity(isHovering ? 1 : 0)
            .animation(.easeOut(duration: 0.18), value: isHovering)
        }
        .onHover { isHovering = $0 }
        .onAppear { scrollPosition = scrollPosition ?? items.first?.id }
        .onChange(of: items.map(\.id)) {
            guard let scrollPosition, items.contains(where: { $0.id == scrollPosition }) else {
                self.scrollPosition = items.first?.id
                return
            }
        }
    }

    @ViewBuilder
    private func shelfButton(direction: Int, systemImage: String) -> some View {
        if !isShelfEdge(direction: direction) {
            Button {
                let visibleCount = max(1, Int(availableWidth / ((itemWidth + spacing) * cardScale)) - 1)
                let currentIndex = scrollPosition.flatMap { current in
                    items.firstIndex(where: { $0.id == current })
                } ?? 0
                let targetIndex = min(max(currentIndex + direction * visibleCount, 0), max(items.count - 1, 0))
                guard items.indices.contains(targetIndex) else { return }
                withAnimation(.snappy) { scrollPosition = items[targetIndex].id }
            } label: {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel(direction < 0 ? "Previous items" : "Next items")
            .allowsHitTesting(isHovering)
        } else {
            Color.clear.frame(width: 1)
        }
    }

    private func isShelfEdge(direction: Int) -> Bool {
        guard !items.isEmpty else { return true }
        let currentIndex = scrollPosition.flatMap { current in
            items.firstIndex(where: { $0.id == current })
        } ?? 0
        return direction < 0 ? currentIndex == 0 : currentIndex >= items.count - 1
    }
}

/// Placeholder shelf shown while a catalog request is in flight.
struct AsterionSkeletonShelf: View {
    var count = 8

    var body: some View {
        // The row is drawn in an overlay so it never widens the page.
        Color.clear
            .frame(height: AsterionCardMetrics.posterShelfHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(0..<count, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            AsterionSkeleton(cornerRadius: 10)
                                .frame(width: AsterionCardMetrics.posterWidth, height: AsterionCardMetrics.posterHeight)
                            AsterionSkeleton(cornerRadius: 3)
                                .frame(width: 110, height: 10)
                            AsterionSkeleton(cornerRadius: 3)
                                .frame(width: 70, height: 8)
                        }
                    }
                }
                .fixedSize()
                .padding(.leading, AsterionLayout.pageInset)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Skeleton for grid-style catalog sections. Scroll-contained so it can
/// never impose a minimum height on the window.
struct AsterionGridSkeleton: View {
    @Environment(\.asterionTopInset) private var chromeInset
    var topInset: CGFloat?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AsterionSkeleton(cornerRadius: 4)
                    .frame(width: 200, height: 16)
                    .padding(.horizontal, AsterionLayout.pageInset)
                AsterionSkeletonShelf()
                AsterionSkeletonShelf()
                AsterionSkeletonShelf()
            }
            .padding(.top, topInset ?? AsterionLayout.catalogContentTop(chromeInset))
        }
        .scrollDisabled(true)
        .hidingScrollIndicators()
        .accessibilityLabel("Loading")
    }
}

/// Opening skeleton for a catalog page: hero band plus two shelves.
struct AsterionCatalogSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: 14) {
                    Spacer()
                    AsterionSkeleton(cornerRadius: 3).frame(width: 90, height: 10)
                    AsterionSkeleton(cornerRadius: 6).frame(width: 340, height: 40)
                    AsterionSkeleton(cornerRadius: 4).frame(width: 300, height: 12)
                    AsterionSkeleton(cornerRadius: 19).frame(width: 150, height: 38)
                        .padding(.top, 8)
                }
                .padding(.horizontal, AsterionLayout.pageInset)
                .padding(.bottom, 44)
                .frame(height: 440, alignment: .bottomLeading)

                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 16) {
                        AsterionSkeleton(cornerRadius: 4)
                            .frame(width: 180, height: 16)
                            .padding(.horizontal, AsterionLayout.pageInset)
                        AsterionSkeletonShelf()
                    }
                }
            }
        }
        .scrollDisabled(true)
        .accessibilityLabel("Loading")
    }
}

// MARK: - Cards

struct HomeContinueCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let item: HomeResumeItem
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                ArtworkImage(url: item.imageURL, fallbackSystemImage: item.systemImage)
                    .frame(width: AsterionCardMetrics.landscapeWidth, height: AsterionCardMetrics.landscapeHeight)
                    .clipped()
                    .scaleEffect(isHovering && !reduceMotion ? 1.04 : 1)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.25),
                        .init(color: .black.opacity(0.55), location: 0.6),
                        .init(color: .black.opacity(0.92), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.subtitle)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text("\(Int(item.percentage.rounded()))%")
                            .font(.asterionMono(11, weight: .medium))
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

                    AsterionLightLine(fraction: item.percentage / 100, height: 3)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 13)

                Image(systemName: item.systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 30)
                    .opacity(isHovering ? 1 : 0)
                    .scaleEffect(isHovering || reduceMotion ? 1 : 0.85)
            }
            .frame(width: AsterionCardMetrics.landscapeWidth, height: AsterionCardMetrics.landscapeHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.55) : Color.white.opacity(isHovering ? 0.22 : 0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .asterionReveal()
        .help("Resume \(item.title)")
        .accessibilityLabel("Resume \(item.title)")
        .accessibilityValue("\(item.subtitle), \(Int(item.percentage.rounded())) percent")
    }
}

struct HomePosterCard: View {
    let item: HomeCatalogItem
    var showsKind = true
    let action: () -> Void

    var body: some View {
        AsterionPosterCard(
            imageURL: item.imageURL,
            badge: showsKind ? item.badge : nil,
            title: item.title,
            subtitle: item.subtitle,
            fallbackSystemImage: item.systemImage,
            action: action
        )
    }
}

/// Artwork with a calm placeholder while loading and an icon on failure.
struct ArtworkImage: View {
    let url: URL?
    var fallbackSystemImage = "photo"

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .empty:
                Color.asterionSurface
            case .failure:
                Color.asterionSurface.overlay {
                    Image(systemName: fallbackSystemImage)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.asterionFaint)
                }
            @unknown default:
                Color.asterionSurface
            }
        }
    }
}

struct AsterionPosterCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let imageURL: URL?
    var badge: String?
    let title: String
    let subtitle: String
    var rank: Int?
    var fallbackSystemImage = "photo"
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isHovering || isSelected ? Color.asterionText : Color.asterionText.opacity(0.9))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.asterionMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .frame(width: AsterionCardMetrics.posterWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
        .asterionReveal()
        .help(title)
        .accessibilityLabel([rank.map { "Number \($0)" }, title, badge].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkImage(url: imageURL, fallbackSystemImage: fallbackSystemImage)
                .frame(width: AsterionCardMetrics.posterWidth, height: AsterionCardMetrics.posterHeight)
                .clipped()

            if let rank {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                Text("\(rank)")
                    .font(.system(size: 58, weight: .black).width(.compressed))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .padding(.leading, 10)
                    .padding(.bottom, -4)
            }
        }
        .frame(width: AsterionCardMetrics.posterWidth, height: AsterionCardMetrics.posterHeight)
        .overlay(alignment: .topLeading) {
            if let badge {
                Text(badge.uppercased())
                    .font(.system(size: 8.5, weight: .bold).width(.expanded))
                    .tracking(0.9)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: Capsule())
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.white.opacity(0.55) : Color.white.opacity(isHovering ? 0.24 : 0.08),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .background {
            if isHovering {
                ArtworkToneReader(url: imageURL) { tone in
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tone.opacity(0.55))
                        .blur(radius: 22)
                        .offset(y: 10)
                }
                .transition(.opacity)
            }
        }
        .scaleEffect(isHovering && !reduceMotion ? 1.035 : 1, anchor: .bottom)
        .offset(y: isHovering && !reduceMotion ? -3 : 0)
    }
}

/// A fixture card: crests either side, kickoff or live state between them.
struct HomeMatchCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let match: FootballMatch
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(competitionLabel)
                        .font(.system(size: 10, weight: .semibold).width(.expanded))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    status
                }

                Spacer(minLength: 10)

                HStack(alignment: .center, spacing: 10) {
                    team(match.homeTeam)
                    VStack(spacing: 3) {
                        Text(match.isLive ? "vs" : match.kickoff.formatted(date: .omitted, time: .shortened))
                            .font(.asterionMono(match.isLive ? 12 : 15, weight: .semibold))
                            .foregroundStyle(match.isLive ? .white.opacity(0.6) : .white)
                        if !match.isLive {
                            Text(match.kickoff.formatted(.dateTime.weekday(.abbreviated).day()))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                    .frame(width: 74)
                    team(match.awayTeam)
                }

                Spacer(minLength: 6)
            }
            .padding(16)
            .frame(width: AsterionCardMetrics.matchWidth, height: AsterionCardMetrics.matchHeight)
            .background {
                ZStack {
                    Color.asterionSurface
                    ArtworkImage(url: match.posterURL, fallbackSystemImage: "sportscourt")
                        .blur(radius: 18)
                        .opacity(0.45)
                        .scaleEffect(1.2)
                    LinearGradient(
                        colors: [.black.opacity(0.35), .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.55) : Color.white.opacity(isHovering ? 0.22 : 0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .offset(y: isHovering && !reduceMotion ? -3 : 0)
            .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .asterionReveal()
        .help("Open \(match.displayTitle)")
        .accessibilityLabel(match.displayTitle)
        .accessibilityValue(
            match.isLive
                ? "Live, \(match.category)"
                : "\(match.kickoff.formatted(date: .abbreviated, time: .shortened)), \(match.category)"
        )
    }

    /// The feed labels most fixtures only as "football"; show the day instead
    /// of repeating the sport on every card.
    private var competitionLabel: String {
        let category = match.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = ["football", "soccer", ""]
        if generic.contains(category.lowercased()) {
            return match.isLive ? "In play" : match.kickoff.formatted(.relative(presentation: .named))
        }
        return category
    }

    @ViewBuilder
    private var status: some View {
        if match.isLive {
            AsterionLiveBadge()
        } else if match.popular {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityLabel("Popular")
        }
    }

    private func team(_ team: FootballTeam?) -> some View {
        VStack(spacing: 8) {
            FootballBadgeView(team: team, size: 46)
            Text(team?.name ?? "TBD")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Pulsing live indicator: the only place the signal red appears.
struct AsterionLiveBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.asterionLive)
                .frame(width: 6, height: 6)
                .shadow(color: Color.asterionLive.opacity(0.9), radius: isPulsing ? 5 : 1)
                .opacity(isPulsing ? 1 : 0.6)
            Text("LIVE")
                .font(.system(size: 9.5, weight: .heavy).width(.expanded))
                .tracking(1)
                .foregroundStyle(Color.asterionLive)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live")
    }
}

// MARK: - Hero

/// Full-bleed billboard at the top of a catalog. The artwork sits on the
/// right, fades into the room on the left, and casts its tone onto the page.
struct AsterionHero<Metadata: View, Actions: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isHovering = false
    @State private var cycleFill: CGFloat = 0

    let imageURL: URL?
    let fallbackSystemImage: String
    let eyebrow: String
    let title: String
    let summary: String?
    var index = 0
    var count = 1
    var select: ((Int) -> Void)?
    @ViewBuilder let metadata: () -> Metadata
    @ViewBuilder let actions: () -> Actions

    private let cycleDuration: Double = 9

    init(
        imageURL: URL?,
        fallbackSystemImage: String,
        eyebrow: String,
        title: String,
        summary: String?,
        index: Int = 0,
        count: Int = 1,
        select: ((Int) -> Void)? = nil,
        @ViewBuilder metadata: @escaping () -> Metadata,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.imageURL = imageURL
        self.fallbackSystemImage = fallbackSystemImage
        self.eyebrow = eyebrow
        self.title = title
        self.summary = summary
        self.index = index
        self.count = count
        self.select = select
        self.metadata = metadata
        self.actions = actions
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            copy
        }
        .containerRelativeFrame(.vertical) { height, _ in
            min(max(height * 0.66, 440), 640)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ArtworkGlow(url: imageURL, height: 900)
        }
        .onHover { isHovering = $0 }
        .task(id: "\(title)#\(index)") {
            await runCycle()
        }
    }

    private var backdrop: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                ArtworkImage(url: imageURL, fallbackSystemImage: fallbackSystemImage)
                    .frame(width: geometry.size.width * 0.66, height: geometry.size.height)
                    .clipped()
                    .mask {
                        ZStack {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black.opacity(0.85), location: 0.38),
                                    .init(color: .black, location: 0.7),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.55),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
                    .id(imageURL)
                    .transition(.opacity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topTrailing)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: imageURL)
        }
        .accessibilityHidden(true)
    }

    private var copy: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                AsterionEyebrow(text: eyebrow, color: .white.opacity(0.7))

                Text(title)
                    .font(.asterionTitle(46, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 4)
                    .frame(maxWidth: 620, alignment: .leading)
                    .contentTransition(.opacity)

                metadata()
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                if let summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineSpacing(3)
                        .lineLimit(3)
                        .frame(maxWidth: 520, alignment: .leading)
                        .contentTransition(.opacity)
                }

                HStack(spacing: 10) {
                    actions()
                }
                .padding(.top, 6)
            }
            .id(title)
            .transition(.opacity.combined(with: .offset(y: 8)))

            Spacer(minLength: 0)

            if count > 1 {
                pageIndicator
            }
        }
        .animation(reduceMotion ? nil : AsterionMotion.featured, value: title)
        .padding(.horizontal, AsterionLayout.pageInset)
        .padding(.bottom, 40)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { item in
                Button {
                    select?(item)
                } label: {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.26))
                        if item == index {
                            Capsule()
                                .fill(.white)
                                .frame(width: 26 * (reduceMotion ? 1 : cycleFill))
                        }
                    }
                    .frame(width: item == index ? 26 : 6, height: 6)
                    .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Featured item \(item + 1) of \(count)")
                .accessibilityAddTraits(item == index ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: index)
    }

    private func runCycle() async {
        cycleFill = 0
        guard count > 1, select != nil, !reduceMotion else { return }
        await Task.yield()
        withAnimation(.linear(duration: cycleDuration)) {
            cycleFill = 1
        }
        do {
            try await Task.sleep(for: .seconds(cycleDuration))
            while isHovering || scenePhase != .active {
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            return
        }
        select?((index + 1) % count)
    }
}
