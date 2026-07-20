import SwiftUI

struct EditorialCatalogView: View {
    @EnvironmentObject private var model: AppModel
    let section: AppSection
    let novels: [Novel]
    let isSearching: Bool
    @Binding var selectedNovelID: String
    let selectNovel: (Novel) -> Void
    @State private var featuredIndex = 0

    var body: some View {
        Group {
            if (model.isLoadingCatalog || model.catalogState == .idle), novels.isEmpty {
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
                            featuredCard
                                .padding(.horizontal, 32)

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
        .onChange(of: model.featuredNovels) {
            featuredIndex = min(featuredIndex, max(0, min(8, model.featuredNovels.count) - 1))
        }
    }

    @ViewBuilder
    private var featuredCard: some View {
        let novels = Array(model.featuredNovels.prefix(8))
        if !novels.isEmpty {
            let safeIndex = min(featuredIndex, novels.count - 1)
            let novel = novels[safeIndex]
            AsterionFeatureCard(
                imageURL: novel.imageURL.flatMap(URL.init(string:)),
                fallbackSystemImage: "book.closed.fill",
                eyebrow: "FEATURED NOVEL",
                title: novel.title,
                summary: novel.summary
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { $0.isEmpty ? nil : $0 }
                    ?? "A handpicked story from the Asterion library.",
                previous: { moveFeatured(by: -1, novels: novels, selectedIndex: safeIndex) },
                next: { moveFeatured(by: 1, novels: novels, selectedIndex: safeIndex) }
            ) {
                HStack(spacing: 14) {
                    Label(novel.authorDisplayName, systemImage: "person.fill")
                    if let genre = novel.genres?.first {
                        Label(genre, systemImage: "book.closed")
                    }
                    if let rating = novel.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
            } actions: {
                Button { open(novel) } label: {
                    Label("View novel", systemImage: "book.pages")
                        .font(.headline)
                        .frame(width: 132)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .controlSize(.large)
                .tint(.asterionAccent)

                Button {
                    Task { await model.toggleLibrary(novelID: novel.id) }
                } label: {
                    Label(
                        model.libraryNovelIDs.contains(novel.id) ? "Saved" : "Save",
                        systemImage: model.libraryNovelIDs.contains(novel.id) ? "bookmark.fill" : "bookmark"
                    )
                    .frame(width: 86)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .controlSize(.large)
                .disabled(!model.isSignedIn || model.isUpdatingLibrary)
            }
        }
    }

    private func open(_ novel: Novel) {
        selectedNovelID = novel.id
        selectNovel(novel)
    }

    private func moveFeatured(by offset: Int, novels: [Novel], selectedIndex: Int) {
        guard !novels.isEmpty else { return }
        featuredIndex = (selectedIndex + offset + novels.count) % novels.count
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
                    selectNovel(novel)
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
                    selectNovel(entry.novel)
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
