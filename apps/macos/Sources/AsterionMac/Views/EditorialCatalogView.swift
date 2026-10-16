import SwiftUI

struct EditorialCatalogView: View {
    @Environment(\.asterionTopInset) private var topInset
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let section: AppSection
    let novels: [Novel]
    let isSearching: Bool
    @Binding var selectedNovelID: String
    let selectNovel: (Novel) -> Void
    @State private var featuredIndex = 0

    var body: some View {
        Group {
            if (model.isLoadingCatalog || model.catalogState == .idle), novels.isEmpty {
                if showsHero {
                    AsterionCatalogSkeleton()
                } else {
                    AsterionGridSkeleton()
                }
            } else if novels.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AsterionLayout.sectionSpacing) {
                        if isSearching {
                            shelf(
                                title: "Results",
                                subtitle: "\(novels.count) novels",
                                novels: novels,
                                usesVerticalGrid: true
                            )
                        } else if section == .discover {
                            featuredCard

                            if !model.continueReadingEntries.isEmpty {
                                continueReadingShelf
                            }

                            shelf(
                                title: "Featured",
                                subtitle: "Chosen for this week",
                                novels: model.featuredNovels
                            )

                            shelf(
                                title: "Trending",
                                subtitle: "What readers keep returning to",
                                novels: model.trendingNovels
                            )
                        } else {
                            shelf(
                                title: "Rankings",
                                subtitle: "The most-read novels on Asterion",
                                novels: novels,
                                showsRank: section == .rankings,
                                usesVerticalGrid: true
                            )
                        }
                    }
                    .padding(.top, showsHero ? 0 : AsterionLayout.catalogContentTop(topInset))
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
        .background(Color.asterionMediaCanvas)
        .onChange(of: model.featuredNovels) {
            featuredIndex = min(featuredIndex, max(0, min(6, model.featuredNovels.count) - 1))
        }
    }

    private var showsHero: Bool {
        section == .discover && !isSearching
    }

    @ViewBuilder
    private var featuredCard: some View {
        let novels = Array(model.featuredNovels.prefix(6))
        if !novels.isEmpty {
            let safeIndex = min(featuredIndex, novels.count - 1)
            let novel = novels[safeIndex]
            let isSaved = model.libraryNovelIDs.contains(novel.id)
            AsterionHero(
                imageURL: novel.imageURL.flatMap(URL.init(string:)),
                fallbackSystemImage: "book.closed",
                eyebrow: novel.genres?.first.map { "Featured \($0)" } ?? "Featured novel",
                title: novel.title,
                summary: novel.summary
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .flatMap { $0.isEmpty ? nil : $0 },
                index: safeIndex,
                count: novels.count,
                select: { featuredIndex = $0 }
            ) {
                HStack(spacing: 8) {
                    Text(novel.authorDisplayName)
                    if let rating = novel.rating {
                        Text("·")
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                    if let chapters = novel.totalChapters, let count = Int(chapters), count > 0 {
                        Text("·")
                        Text("\(count.formatted()) chapters")
                    }
                }
            } actions: {
                Button { open(novel) } label: {
                    Label("View novel", systemImage: "book.pages")
                }
                .buttonStyle(.asterionPrimary)

                Button {
                    Task { await model.toggleLibrary(novelID: novel.id) }
                } label: {
                    Label(
                        isSaved ? "In library" : "Add to library",
                        systemImage: isSaved ? "checkmark" : "plus"
                    )
                }
                .buttonStyle(.asterionSecondary)
                .disabled(!model.isSignedIn || model.isUpdatingLibrary)
                .help(model.isSignedIn ? "" : "Sign in to keep a library")
            }
        }
    }

    private func open(_ novel: Novel) {
        selectedNovelID = novel.id
        selectNovel(novel)
    }

    private func shelf(
        title: String,
        subtitle: String,
        novels: [Novel],
        showsRank: Bool = false,
        usesVerticalGrid: Bool = false
    ) -> some View {
        HomeSection(title: title, subtitle: subtitle) {
            if usesVerticalGrid {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: AsterionCardMetrics.posterWidth, maximum: AsterionCardMetrics.posterWidth), spacing: 20)],
                    alignment: .leading,
                    spacing: 28
                ) {
                    ForEach(novels) { novel in
                        bookTile(novel, showsRank: showsRank)
                    }
                }
                .padding(.horizontal, AsterionLayout.pageInset)
            } else {
                HomeHorizontalShelf(
                    items: novels,
                    itemWidth: AsterionCardMetrics.posterWidth,
                    spacing: 18,
                    height: AsterionCardMetrics.posterShelfHeight
                ) { novel in
                    bookTile(novel, showsRank: showsRank)
                }
            }
        }
    }

    private func bookTile(_ novel: Novel, showsRank: Bool) -> some View {
        EditorialBookTile(
            novel: novel,
            isSelected: selectedNovelID == novel.id,
            rank: showsRank && novel.numericRank != .max ? novel.numericRank : nil
        ) {
            selectedNovelID = novel.id
            selectNovel(novel)
        }
        .contextMenu { libraryContextMenu(for: novel) }
    }

    private var continueReadingShelf: some View {
        HomeSection(title: "Continue reading", subtitle: "Pick up where you left off") {
            HomeHorizontalShelf(
                items: model.continueReadingEntries,
                itemWidth: AsterionCardMetrics.landscapeWidth,
                spacing: 16,
                height: AsterionCardMetrics.landscapeShelfHeight
            ) { entry in
                HomeContinueCard(
                    item: .reading(entry),
                    isSelected: selectedNovelID == entry.novel.id
                ) {
                    selectedNovelID = entry.novel.id
                    openWindow(
                        value: ReaderRoute(
                            novelID: entry.novel.id,
                            chapterID: entry.progress.chapterId
                        )
                    )
                }
                .contextMenu {
                    Button("Show Details") {
                        selectedNovelID = entry.novel.id
                        selectNovel(entry.novel)
                    }
                    Divider()
                    libraryContextMenu(for: entry.novel)
                }
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
        AsterionEmptyState(
            systemImage: isSearching ? "magnifyingglass" : "books.vertical",
            title: isSearching ? "No novels match" : "No novels yet",
            message: isSearching
                ? "Try a shorter title, an author, or a genre."
                : "The novel catalog is empty right now. Check your connection and reopen this page."
        )
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
            title: novel.title,
            subtitle: novel.authorDisplayName,
            rank: rank,
            fallbackSystemImage: "book.closed",
            isSelected: isSelected,
            action: action
        )
        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: isSelected)
        .accessibilityValue("by \(novel.authorDisplayName)")
    }
}
