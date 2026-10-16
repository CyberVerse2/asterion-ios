import AsterionKit
import SwiftUI

/// Browse → Novels → Ranking: the catalog ordered by rank, rating or views,
/// with the top three on a podium and the rest in a numbered panel. It is a
/// section of `NovelCatalogView`, which loads the catalog, pushes details,
/// and shows the loading, error and empty states.
struct RankingView: View {
    let novels: [Novel]
    @State private var sortBy: NovelCatalog.RankingSort = .rank

    private var sorted: [Novel] { NovelCatalog.ranking(novels, by: sortBy) }

    private var caption: String {
        switch sortBy {
        case .rank: "The novels readers return to most."
        case .rating: "The highest rated novels first."
        case .views: "The most read novels first."
        }
    }

    var body: some View {
        let entries = sorted.enumerated().map { index, novel in
            RankedNovel(novel: novel, rank: index + 1)
        }
        let podium = Array(entries.prefix(3))
        let rest = Array(entries.dropFirst(3))

        VStack(alignment: .leading, spacing: 18) {
            CatalogFilterChips(
                items: NovelCatalog.RankingSort.allCases,
                title: { $0.rawValue },
                selection: $sortBy
            )

            Text(caption)
                .font(.asterionReading(13.5))
                .foregroundStyle(Color.asterionMuted)

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
            .padding(.top, 4)

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
                .padding(.top, 10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: sortBy)
    }
}

private struct RankedNovel: Identifiable {
    let novel: Novel
    let rank: Int
    var id: String { novel.id }

    var metadata: String {
        var parts: [String] = []
        if let rating = novel.ratingLabel { parts.append(rating) }
        if let views = novel.views?.trimmingCharacters(in: .whitespacesAndNewlines), !views.isEmpty {
            parts.append(views.localizedCaseInsensitiveContains("view") ? views : views + " views")
        }
        if let chapters = novel.catalogChapterCount { parts.append(String(chapters) + " ch") }
        if let status = novel.statusTitle { parts.append(status) }
        return parts.joined(separator: " · ")
    }

    var accessibilityText: String {
        "Rank " + String(rank) + ", " + novel.title + ", by " + (novel.author ?? "unknown author")
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
                        Text(verbatim: String(entry.rank))
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
                Text(entry.novel.compactMetadata.isEmpty ? (entry.novel.author ?? "Novel") : entry.novel.compactMetadata)
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
            Text(verbatim: String(entry.rank))
                .font(.rankNumeral(entry.rank >= 100 ? 24 : 32))
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
