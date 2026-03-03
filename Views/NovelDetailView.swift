import Inject
import SwiftUI

struct NovelDetailView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var tabBarState: TabBarState
    @Environment(\.dismiss) private var dismiss
    let novel: Novel

    @State private var chapters: [Chapter] = []
    @State private var totalChapters = 0
    @State private var loadingChapters = false
    @State private var chapterError: String?
    @State private var synopsisExpanded = false
    @State private var allNovels: [Novel] = []

    private let previewCount = 5
    private var genreColor: Color { GenreStyle.color(for: novel.genres) }

    private var similarNovels: [Novel] {
        allNovels
            .filter { $0.id != novel.id && $0.genres?.contains(where: { novel.genres?.contains($0) == true }) == true }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                metaStatsSection
                genrePillsSection
                synopsisSection
                startReadingButton
                chapterPreviewSection
                similarNovelsSection
            }
            .padding(.bottom, 100)
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Text("← Back")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.asterionCard.opacity(0.5))
                            .stroke(Color.asterionBorder, lineWidth: 1)
                    )
            }
            .padding(.top, 54)
            .padding(.leading, 20)
        }
        .background(Color.asterionBackground.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await loadInitialData() }
        .onAppear { tabBarState.isVisible = false }
        .onDisappear { tabBarState.isVisible = true }
        .enableInjection()
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            LinearGradient(
                colors: [genreColor.opacity(0.1), Color.asterionBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            MazePatternView()

            VStack(spacing: 0) {
                Spacer().frame(height: 120)

                CoverImageView(novel: novel, size: .lg)
                    .padding(.bottom, 24)

                Text(novel.title)
                    .font(.asterionSerif(26, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 40)

                Text(novel.author ?? "Unknown")
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.asterionMuted)
                    .padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
        .frame(height: 420)
    }

    // MARK: - Metadata Stats

    private var metaStatsSection: some View {
        let items: [(String, String)] = [
            novel.rank.map { ("Rank", "#\($0)") },
            novel.rating.map { ("Rating", "★ \(String(format: "%.1f", $0))") },
            novel.totalChapters.map { ("Chapters", $0) },
            novel.status.map { ("Status", $0) },
            novel.views.map { ("Views", $0) },
        ].compactMap { $0 }

        return HStack(spacing: 28) {
            ForEach(items, id: \.0) { item in
                VStack(spacing: 4) {
                    Text(item.1)
                        .font(.asterionSerif(15, weight: .semibold))
                        .foregroundStyle(Color.asterionText)
                    Text(item.0.uppercased())
                        .font(.asterionMono(9))
                        .foregroundStyle(Color.asterionDim)
                        .tracking(2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.asterionCard).frame(height: 1)
        }
    }

    // MARK: - Genre Pills

    @ViewBuilder
    private var genrePillsSection: some View {
        if let genres = novel.genres, !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        Text(genre)
                            .font(.asterionMono(11))
                            .foregroundStyle(genreColor.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(genreColor.opacity(0.05))
                                    .stroke(genreColor.opacity(0.15), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Synopsis

    @ViewBuilder
    private var synopsisSection: some View {
        if let summary = novel.summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("SYNOPSIS")
                    .font(.asterionMono(10))
                    .foregroundStyle(Color.asterionDim)
                    .tracking(3)

                Text(summary)
                    .font(.asterionSerif(16))
                    .foregroundStyle(Color.asterionSynopsis)
                    .lineSpacing(6)
                    .lineLimit(synopsisExpanded ? nil : 4)

                if summary.count > 200 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            synopsisExpanded.toggle()
                        }
                    } label: {
                        Text(synopsisExpanded ? "Show less" : "Read more")
                            .font(.asterionMono(12))
                            .foregroundStyle(Color.goldAccent)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Start Reading

    @ViewBuilder
    private var startReadingButton: some View {
        if let first = chapters.first {
            NavigationLink {
                ReaderView(
                    initialChapter: first,
                    novel: novel,
                    allChapters: chapters
                )
            } label: {
                Text("Start Reading")
                    .font(.asterionSerif(17, weight: .semibold))
                    .foregroundStyle(Color.asterionBackground)
                    .tracking(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [genreColor, genreColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .shadow(color: genreColor.opacity(0.3), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Chapter Preview

    private var chapterPreviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CHAPTERS")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionDim)
                .tracking(3)

            if loadingChapters {
                HStack {
                    Spacer()
                    ProgressView().tint(Color.goldAccent)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let error = chapterError {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.asterionMono(13))
                        .foregroundStyle(Color.asterionMuted)
                    Button("Try Again") {
                        Task { await loadChapters() }
                    }
                    .font(.asterionMono(12))
                    .foregroundStyle(Color.goldAccent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if chapters.isEmpty {
                Text("No chapters available yet")
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.asterionDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    let preview = Array(chapters.prefix(previewCount))
                    ForEach(Array(preview.enumerated()), id: \.element.id) { index, chapter in
                        NavigationLink {
                            ReaderView(
                                initialChapter: chapter,
                                novel: novel,
                                allChapters: chapters
                            )
                        } label: {
                            HStack(spacing: 10) {
                                Text("#\(chapter.chapterNumber)")
                                    .font(.asterionMono(10))
                                    .foregroundStyle(Color.asterionDim)
                                    .frame(width: 36, alignment: .leading)

                                Text(chapter.title)
                                    .font(.asterionSerif(15))
                                    .foregroundStyle(Color.asterionReaderText)
                                    .lineLimit(1)

                                Spacer()

                                Text("›")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.asterionBorder)
                            }
                            .padding(.vertical, 13)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)

                        if index < preview.count - 1 {
                            Divider().overlay(Color.asterionCard)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.asterionBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

                NavigationLink {
                    ChaptersView(novel: novel, allChapters: chapters, totalCount: totalChapters)
                } label: {
                    HStack(spacing: 8) {
                        Text("View All Chapters")
                            .font(.asterionMono(13))
                            .foregroundStyle(Color.goldAccent)
                        Text("→")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.goldAccent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.asterionBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    // MARK: - Similar Novels

    @ViewBuilder
    private var similarNovelsSection: some View {
        if !similarNovels.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("YOU'LL LIKE MORE OF THESE")
                    .font(.asterionMono(10))
                    .foregroundStyle(Color.asterionMuted)
                    .tracking(2)
                    .padding(.horizontal, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(similarNovels, id: \.id) { n in
                            NavigationLink {
                                NovelDetailView(novel: n)
                            } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    CoverImageView(novel: n, size: .tile)
                                        .padding(.bottom, 8)

                                    Text(n.title)
                                        .font(.asterionSerif(13, weight: .medium))
                                        .foregroundStyle(Color.asterionText)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    Text(n.author ?? "Unknown")
                                        .font(.asterionMono(10))
                                        .foregroundStyle(Color.asterionMuted)
                                        .padding(.top, 3)

                                    if let rating = n.rating {
                                        Text("★ \(String(format: "%.1f", rating))")
                                            .font(.asterionMono(10))
                                            .foregroundStyle(Color.goldAccent)
                                            .padding(.top, 4)
                                    }
                                }
                                .frame(width: 130)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Data

    private func loadInitialData() async {
        async let chaptersTask: () = loadChapters()
        async let novelsTask: () = loadAllNovels()
        _ = await (chaptersTask, novelsTask)
    }

    private func loadChapters() async {
        loadingChapters = true
        chapterError = nil
        defer { loadingChapters = false }
        do {
            let response = try await apiClient.fetchChapters(
                novelId: novel.id,
                limit: previewCount,
                offset: 0
            )
            chapters = response.data
            totalChapters = response.meta?.count ?? response.data.count
        } catch {
            chapterError = error.localizedDescription
        }
    }

    private func loadAllNovels() async {
        do { allNovels = try await apiClient.fetchNovels(limit: 100) } catch {}
    }
}
