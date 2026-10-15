import Inject
import SwiftUI

struct RankingView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @State private var novels: [Novel] = []
    @State private var loading = false
    @State private var failed = false
    @State private var sortBy: SortOption = .rank
    @State private var navigationPath: [Novel] = []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var contentMaxWidth: CGFloat { AsterionLayout.pageMaxWidth(horizontalSizeClass) }
    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }

    enum SortOption: String, CaseIterable {
        case rank = "By rank"
        case rating = "By rating"
        case views = "By views"
    }

    private var sorted: [Novel] {
        switch sortBy {
        case .rank:
            return Novel.ranked(novels)
        case .rating:
            return novels.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .views:
            return novels.sorted {
                parseViews($0.views) > parseViews($1.views)
            }
        }
    }

    private func parseViews(_ v: String?) -> Int {
        parsedInteger(v, fallback: 0)
    }

    private func parsedInteger(_ raw: String?, fallback: Int) -> Int {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return fallback
        }

        // Handles formats like:
        // - "12345"
        // - "12,345"
        // - "1.2K", "3.4M", "1.1B"
        // - "987 views"
        let compact = raw
            .replacingOccurrences(of: "views", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "rank", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if let suffix = compact.last, ["K", "M", "B"].contains(suffix) {
            let numberPart = String(compact.dropLast())
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(numberPart) else { return fallback }
            let multiplier: Double
            switch suffix {
            case "K": multiplier = 1_000
            case "M": multiplier = 1_000_000
            case "B": multiplier = 1_000_000_000
            default: multiplier = 1
            }
            return Int(value * multiplier)
        }

        let digitsOnly = compact.filter { $0.isNumber || $0 == "," }
            .replacingOccurrences(of: ",", with: "")
        return Int(digitsOnly) ?? fallback
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AsterionPageHeader(title: "Rankings", subtitle: pageSubtitle)
                        .padding(.horizontal, pageHorizontalPadding)
                        .padding(.bottom, 10)

                    sortTabs

                    if loading && novels.isEmpty {
                        loadingState
                    } else if failed && novels.isEmpty {
                        VStack(spacing: 0) {
                            AsterionEmptyState(
                                symbol: "wifi.exclamationmark",
                                title: "Rankings could not be loaded",
                                message: "Check your connection, then try again."
                            )
                            Button {
                                Task { await loadNovels() }
                            } label: {
                                Text("Try again")
                                    .font(.asterionReading(15, weight: .semibold))
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(AsterionOutlineButtonStyle())
                            .padding(.top, -24)
                        }
                        .frame(maxWidth: .infinity)
                    } else if sorted.isEmpty {
                        AsterionEmptyState(
                            symbol: "list.number",
                            title: "No rankings yet",
                            message: "The catalog is empty right now. Pull down to refresh."
                        )
                    } else {
                        rankingContent
                    }
                }
                .padding(.bottom, 40)
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .refreshable { await loadNovels() }
            .background { AsterionBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Novel.self) { novel in
                NovelDetailView(novel: novel) {
                    popNovelPath()
                }
            }
            .task { await loadNovels() }
        }
        .enableInjection()
    }

    private func popNovelPath() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
    }

    private var pageSubtitle: String {
        switch sortBy {
        case .rank: "The novels readers return to most."
        case .rating: "The highest rated novels first."
        case .views: "The most viewed novels first."
        }
    }

    // MARK: - Sort

    private var sortTabs: some View {
        AsterionIndexTabs(
            items: SortOption.allCases,
            title: { $0.rawValue },
            rank: .section,
            selection: $sortBy
        )
        .padding(.horizontal, pageHorizontalPadding - 20)
        .padding(.bottom, 14)
    }

    // MARK: - Ranking

    private var rankingContent: some View {
        let entries = Array(sorted.enumerated()).map { index, novel in
            RankedNovel(novel: novel, rank: rankNumber(for: novel, position: index + 1))
        }
        let podium = Array(entries.prefix(3))
        let rest = Array(entries.dropFirst(3))

        return VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(podium) { entry in
                    NavigationLink(value: entry.novel) {
                        RankingPodiumTile(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(0..<max(0, 3 - podium.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                }
            }

            if !rest.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(value: entry.novel) {
                            RankingRow(entry: entry, showsSeparator: index < rest.count - 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .asterionPanel(cornerRadius: 16)
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
        .animation(.easeInOut(duration: 0.25), value: sortBy)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    AsterionSkeleton(cornerRadius: 10)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: 14) {
                        AsterionSkeleton(cornerRadius: 4).frame(width: 26, height: 26)
                        AsterionSkeleton(cornerRadius: 8).frame(width: 44, height: 66)
                        VStack(alignment: .leading, spacing: 8) {
                            AsterionSkeleton(cornerRadius: 4).frame(width: 160, height: 12)
                            AsterionSkeleton(cornerRadius: 4).frame(width: 100, height: 10)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .asterionPanel(cornerRadius: 16)
        }
        .padding(.horizontal, pageHorizontalPadding)
        .accessibilityElement()
        .accessibilityLabel("Loading rankings")
    }

    // MARK: - Data

    private func loadNovels() async {
        loading = true
        defer { loading = false }
        do {
            novels = try await apiClient.fetchAllNovels()
            await OfflineChapterStore.shared.saveCatalog(novels)
            failed = false
        } catch {
            let cached = await OfflineChapterStore.shared.loadCatalog()
            if !cached.isEmpty {
                novels = cached
                failed = false
            } else if novels.isEmpty {
                failed = true
            }
        }
    }

    private func rankNumber(for novel: Novel, position: Int) -> Int {
        if sortBy == .rank, novel.rankPosition != .max {
            return novel.rankPosition
        }
        return position
    }
}

private struct RankedNovel: Identifiable {
    let novel: Novel
    let rank: Int
    var id: String { novel.id }

    var metadata: String {
        var parts: [String] = []
        if let rating = novel.rating {
            parts.append("★ \(String(format: "%.1f", rating))")
        }
        if let views = novel.views?.trimmingCharacters(in: .whitespacesAndNewlines), !views.isEmpty {
            parts.append(views.localizedCaseInsensitiveContains("view") ? views : "\(views) views")
        }
        if let status = novel.status?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
            parts.append(status.localizedCapitalized)
        }
        return parts.joined(separator: " · ")
    }

    var accessibilityText: String {
        "Rank \(rank), \(novel.title), by \(novel.author ?? "unknown author")"
    }
}

/// Compressed black numerals: the rank reads as part of the poster.
private extension Font {
    static func rankNumeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.compressed)
    }
}

// MARK: - Podium

private struct RankingPodiumTile: View {
    let entry: RankedNovel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { NovelPosterArt(novel: entry.novel) }
                .overlay(alignment: .bottomLeading) {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        Text("\(entry.rank)")
                            .font(.rankNumeral(58))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .shadow(color: .black.opacity(0.5), radius: 8)
                            .padding(.leading, 8)
                            .padding(.bottom, -6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.asterionBorder)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.novel.title)
                    .font(.asterionReading(13, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(entry.novel.author ?? "Unknown author")
                    .font(.asterionReading(11.5))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityText)
    }
}

// MARK: - Ranking Row

private struct RankingRow: View {
    let entry: RankedNovel
    let showsSeparator: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text("\(entry.rank)")
                .font(.rankNumeral(entry.rank >= 1000 ? 22 : 32))
                .foregroundStyle(Color.asterionText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 38, alignment: .center)

            NovelPosterArt(novel: entry.novel)
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.asterionBorder)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.novel.title)
                    .font(.asterionReading(14.5, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)

                Text(entry.novel.author ?? "Unknown author")
                    .font(.asterionReading(12.5))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)

                if !entry.metadata.isEmpty {
                    Text(entry.metadata)
                        .font(.asterionMono(10.5, weight: .medium))
                        .foregroundStyle(Color.asterionFaint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.asterionFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Color.asterionHairline)
                    .frame(height: 1)
                    .padding(.leading, 14 + 38 + 14)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityText)
        .accessibilityValue(entry.metadata)
    }
}
