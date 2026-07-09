import SwiftUI

struct EditorialCatalogView: View {
    @EnvironmentObject private var model: AppModel
    let section: AppSection
    let novels: [Novel]
    let isSearching: Bool
    @Binding var selectedNovelID: String

    private let columns = [
        GridItem(.adaptive(minimum: 118, maximum: 154), spacing: 22, alignment: .top),
    ]

    var body: some View {
        Group {
            if model.isLoadingCatalog, novels.isEmpty {
                ProgressView("Curating your shelves…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if novels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 34) {
                        if isSearching {
                            shelf(
                                title: "Search Results",
                                subtitle: "Titles matching your search.",
                                novels: novels
                            )
                        } else if section == .discover {
                            shelf(
                                title: "Featured",
                                subtitle: "Handpicked stories worth your time.",
                                novels: model.featuredNovels,
                                horizontal: true
                            )

                            if !model.continueReadingEntries.isEmpty {
                                continueReadingShelf
                            }

                            shelf(
                                title: "Trending This Week",
                                subtitle: "Stories readers keep returning to.",
                                novels: model.trendingNovels,
                                horizontal: true
                            )
                        } else {
                            shelf(
                                title: section.title,
                                subtitle: section == .rankings
                                    ? "The most-loved stories in Asterion."
                                    : "Your saved stories, ready whenever you are.",
                                novels: novels,
                                showsRank: section == .rankings
                            )
                        }
                    }
                    .frame(maxWidth: 920, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
        .background(Color.asterionBackground)
    }

    private func shelf(
        title: String,
        subtitle: String,
        novels: [Novel],
        showsRank: Bool = false,
        horizontal: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ShelfHeader(title: title, subtitle: subtitle)
            if horizontal {
                ViewThatFits(in: .horizontal) {
                    bookRow(novels: novels, showsRank: showsRank, count: 4)
                    bookRow(novels: novels, showsRank: showsRank, count: 3)
                    bookRow(novels: novels, showsRank: showsRank, count: 2)
                }
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                    bookTiles(novels: novels, showsRank: showsRank)
                }
            }
        }
    }

    private func bookRow(novels: [Novel], showsRank: Bool, count: Int) -> some View {
        HStack(alignment: .top, spacing: 22) {
            bookTiles(novels: Array(novels.prefix(count)), showsRank: showsRank)
        }
    }

    @ViewBuilder
    private func bookTiles(novels: [Novel], showsRank: Bool) -> some View {
        ForEach(novels) { novel in
            EditorialBookTile(
                novel: novel,
                isSelected: selectedNovelID == novel.id,
                rank: showsRank && novel.numericRank != .max ? novel.numericRank : nil
            ) {
                selectedNovelID = novel.id
            }
            .contextMenu { libraryContextMenu(for: novel) }
        }
    }

    private var continueReadingShelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            ShelfHeader(title: "Continue Reading", subtitle: "Pick up where you left off.")
            ViewThatFits(in: .horizontal) {
                continueReadingRow(count: 4)
                continueReadingRow(count: 3)
                continueReadingRow(count: 2)
            }
        }
    }

    private func continueReadingRow(count: Int) -> some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(model.continueReadingEntries.prefix(count)) { entry in
                ContinueReadingTile(
                    entry: entry,
                    isSelected: selectedNovelID == entry.novel.id
                ) {
                    selectedNovelID = entry.novel.id
                }
                .contextMenu { libraryContextMenu(for: entry.novel) }
            }
        }
    }

    @ViewBuilder
    private func libraryContextMenu(for novel: Novel) -> some View {
        Button(model.libraryNovelIDs.contains(novel.id) ? "Remove from Library" : "Add to Library") {
            Task { await model.toggleLibrary(novelID: novel.id) }
        }
        .disabled(!model.isSignedIn)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                section == .library ? "Your library is empty" : "No novels found",
                systemImage: section == .library ? "books.vertical" : "magnifyingglass"
            )
        } description: {
            if section == .library, !model.isSignedIn {
                Text("Sign in from Account to sync your library.")
            } else if section == .library {
                Text("Save a novel from its detail page and it will appear here.")
            } else {
                Text("Try a different title, author, or genre.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.asterionBackground)
    }
}

private struct ShelfHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.asterionDisplay(22, weight: .semibold))
                .foregroundStyle(Color.asterionText)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Color.asterionMuted)
        }
    }
}

private struct EditorialBookTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let novel: Novel
    let isSelected: Bool
    let rank: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    CoverView(novel: novel, width: 128, height: 184)
                    if let rank {
                        Text("#\(rank)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.asterionAccent, in: Capsule())
                            .padding(7)
                    }
                }
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isSelected ? Color.asterionAccent : .clear, lineWidth: 2)
                }

                Text(novel.title)
                    .font(.asterionDisplay(15, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .frame(maxWidth: 136, alignment: .leading)

                Text(novel.authorDisplayName)
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                    .frame(maxWidth: 136, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AsterionPressButtonStyle())
        .asterionHoverLift()
        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: isSelected)
        .accessibilityLabel("\(novel.title), by \(novel.authorDisplayName)")
    }
}

private struct ContinueReadingTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: AppModel.ContinueReadingEntry
    let isSelected: Bool
    let action: () -> Void

    private var fraction: Double {
        min(1, max(0, entry.progress.percentage / 100))
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                CoverView(novel: entry.novel, width: 112, height: 160)
                    .padding(4)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.asterionAccent : .clear, lineWidth: 2)
                    }
                Text(entry.novel.title)
                    .font(.asterionDisplay(14, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(2)
                    .frame(maxWidth: 120, alignment: .leading)
                Text("Chapter progress · \(Int(entry.progress.percentage))%")
                    .font(.caption2)
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                ProgressView(value: fraction)
                    .tint(Color.asterionAccent)
                    .frame(maxWidth: 120)
            }
        }
        .buttonStyle(AsterionPressButtonStyle())
        .asterionHoverLift()
        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: isSelected)
    }
}
