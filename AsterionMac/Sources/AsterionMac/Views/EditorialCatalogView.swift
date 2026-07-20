import SwiftUI

struct EditorialCatalogView: View {
    @EnvironmentObject private var model: AppModel
    let section: AppSection
    let novels: [Novel]
    let isSearching: Bool
    @Binding var selectedNovelID: String

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
                                novels: model.featuredNovels
                            )

                            if !model.continueReadingEntries.isEmpty {
                                continueReadingShelf
                            }

                            shelf(
                                title: "Trending This Week",
                                subtitle: "Stories readers keep returning to.",
                                novels: model.trendingNovels
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
                    .padding(.top, 32)
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
        .background(Color.asterionMediaCanvas)
    }

    private func shelf(
        title: String,
        subtitle: String,
        novels: [Novel],
        showsRank: Bool = false
    ) -> some View {
        HomeSection(title: title, subtitle: subtitle) {
            HomeHorizontalShelf(
                items: novels,
                itemWidth: 168,
                spacing: 18,
                height: 258
            ) { novel in
                EditorialBookTile(
                    novel: novel,
                    isSelected: selectedNovelID == novel.id,
                    rank: showsRank && novel.numericRank != .max ? novel.numericRank : nil
                ) {
                    selectedNovelID = novel.id
                }
                .padding(.vertical, 3)
                .contextMenu { libraryContextMenu(for: novel) }
            }
        }
    }

    private var continueReadingShelf: some View {
        HomeSection(title: "Continue Reading", subtitle: "Pick up where you left off.") {
            HomeHorizontalShelf(
                items: model.continueReadingEntries,
                itemWidth: 294,
                spacing: 18,
                height: 172
            ) { entry in
                HomeContinueCard(
                    item: .reading(entry),
                    isSelected: selectedNovelID == entry.novel.id
                ) {
                    selectedNovelID = entry.novel.id
                }
                .padding(.vertical, 3)
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
            Label("No novels found", systemImage: "magnifyingglass")
        } description: {
            Text("Try a different title, author, or genre.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.asterionMediaCanvas)
    }
}

private struct EditorialBookTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let novel: Novel
    let isSelected: Bool
    let rank: Int?
    let action: () -> Void

    var body: some View {
        AsterionPosterCard(
            imageURL: novel.imageURL.flatMap(URL.init(string:)),
            badge: rank.map { "#\($0)" } ?? "NOVEL",
            title: novel.title,
            subtitle: novel.authorDisplayName,
            isSelected: isSelected,
            action: action
        )
        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: isSelected)
        .accessibilityValue("by \(novel.authorDisplayName)")
    }
}
