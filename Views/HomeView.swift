import Inject
import SwiftUI

struct HomeView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @State private var novels: [Novel] = []
    @State private var loading = false
    @State private var failed = false
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var showAll = false

    private let initialCount = 6

    private var displayNovels: [Novel] {
        if !debouncedSearch.isEmpty || showAll { return novels }
        return Array(novels.prefix(initialCount))
    }

    private struct ContinueReadingItem: Identifiable {
        let novel: Novel
        let chapterNum: Int
        let chapterTitle: String
        var id: String { novel.id }
    }

    private static let seedProgress: [(chapterNum: Int, chapterTitle: String)] = [
        (847, "Nightmare's Edge"),
        (312, "The Fool's Gambit"),
    ]

    private var continueReading: [ContinueReadingItem] {
        novels.prefix(2).enumerated().compactMap { idx, novel in
            guard idx < Self.seedProgress.count else { return nil }
            let seed = Self.seedProgress[idx]
            return ContinueReadingItem(novel: novel, chapterNum: seed.chapterNum, chapterTitle: seed.chapterTitle)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    searchSection

                    if loading && novels.isEmpty {
                        loadingSection
                    } else if failed && novels.isEmpty {
                        errorSection
                    } else if novels.isEmpty {
                        emptySection
                    } else {
                        contentSection
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await loadNovels(search: debouncedSearch) }
            .background {
                Color.asterionBackground.ignoresSafeArea()
                MazePatternView().ignoresSafeArea()
            }
            .navigationTitle("Asterion")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: Novel.self) { novel in
                NovelDetailView(novel: novel)
            }
        .task { await loadNovels() }
        .debounceSearch(text: $search, debouncedText: $debouncedSearch)
        .onChange(of: debouncedSearch) { _, newValue in
            Task { await loadNovels(search: newValue) }
        }
        }
        .enableInjection()
    }

    // MARK: - Search

    private var searchSection: some View {
        SearchInputView(text: $search, placeholder: "Search novels...")
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
    }

    // MARK: - Loading / Error / Empty

    private var loadingSection: some View {
        HStack {
            Spacer()
            ProgressView()
                .tint(Color.goldAccent)
                .scaleEffect(1.2)
                .padding(40)
            Spacer()
        }
    }

    private var errorSection: some View {
        VStack(spacing: 12) {
            Text("⚠")
                .font(.system(size: 32))
                .opacity(0.4)
            Text(failed ? "Couldn't load novels" : "")
                .font(.asterionMono(13))
                .foregroundStyle(Color.asterionMuted)
            Button {
                Task { await loadNovels(search: debouncedSearch) }
            } label: {
                Text("Try Again")
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.goldAccent)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .overlay(
                        Capsule().stroke(Color.asterionBorder, lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var emptySection: some View {
        VStack(spacing: 12) {
            Text("📚")
                .font(.system(size: 36))
                .opacity(0.3)
            Text(debouncedSearch.isEmpty ? "No novels found" : "No novels match your search")
                .font(.asterionMono(13))
                .foregroundStyle(Color.asterionDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        if debouncedSearch.isEmpty && !continueReading.isEmpty {
            continueReadingSection
        }
        browseGridSection
    }

    // MARK: - Continue Reading

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CONTINUE READING")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionMuted)
                .tracking(3)

            ForEach(continueReading) { item in
                NavigationLink(value: item.novel) {
                    ContinueReadingCard(
                        novel: item.novel,
                        chapterNum: item.chapterNum,
                        chapterTitle: item.chapterTitle
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // MARK: - Browse Grid

    private var browseGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(debouncedSearch.isEmpty ? "BROWSE ALL" : "Results for \"\(debouncedSearch)\"")
                .font(.asterionMono(10))
                .foregroundStyle(Color.asterionMuted)
                .tracking(debouncedSearch.isEmpty ? 3 : 0)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(Array(displayNovels.enumerated()), id: \.element.id) { index, novel in
                    NavigationLink(value: novel) {
                        NovelTileCard(novel: novel)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.06), value: novels.count)
                }
            }

            if debouncedSearch.isEmpty && !showAll && novels.count > initialCount {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { showAll = true }
                } label: {
                    Text("Show More (\(novels.count - initialCount) more)")
                        .font(.asterionMono(13))
                        .foregroundStyle(Color.asterionMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.asterionCard.opacity(0.25))
                                .stroke(Color.asterionBorder, lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Data

    private func loadNovels(search: String = "") async {
        loading = true
        defer { loading = false }
        do {
            novels = try await apiClient.fetchNovels(limit: 50, search: search)
            failed = false
        } catch {
            if novels.isEmpty { failed = true }
        }
    }
}

// MARK: - Continue Reading Card

private struct ContinueReadingCard: View {
    let novel: Novel
    let chapterNum: Int
    let chapterTitle: String

    private var color: Color { GenreStyle.color(for: novel.genres) }

    private var totalCh: Int {
        Int(novel.totalChapters?.filter(\.isNumber) ?? "") ?? 1
    }
    private var pct: Double {
        min(100, Double(chapterNum) / Double(max(1, totalCh)) * 100)
    }

    var body: some View {
        HStack(spacing: 14) {
            CoverImageView(novel: novel, size: .md)

            VStack(alignment: .leading, spacing: 3) {
                Text(novel.title)
                    .font(.asterionSerif(17, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)

                Text("Ch. \(chapterNum) · \(chapterTitle)")
                    .font(.asterionMono(11))
                    .foregroundStyle(Color.asterionDim)

                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.asterionBorder)

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [color, color.opacity(0.65)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * pct / 100)
                        }
                    }
                    .frame(height: 3)

                    Text("\(Int(pct))%")
                        .font(.asterionMono(10))
                        .foregroundStyle(Color.asterionDim)
                        .fixedSize()
                }
                .padding(.top, 7)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.asterionCard, Color.asterionCardHover],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .stroke(Color.asterionBorder, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0), color, color.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .opacity(0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Novel Tile Card

private struct NovelTileCard: View {
    let novel: Novel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let rank = novel.rank {
                HStack {
                    Spacer()
                    Text("#\(rank)")
                        .font(.asterionMono(9))
                        .foregroundStyle(Color.asterionDim)
                }
            }

            CoverImageView(novel: novel, size: .tile)
                .padding(.bottom, 8)

            Text(novel.title)
                .font(.asterionSerif(15, weight: .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(novel.author ?? "Unknown")
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionMuted)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let rating = novel.rating {
                    Text("★ \(String(format: "%.1f", rating))")
                        .font(.asterionMono(10))
                        .foregroundStyle(Color.goldAccent)
                }
                if let status = novel.status {
                    StatusPill(status: status)
                }
            }
            .padding(.top, 4)

            if let chapters = novel.totalChapters {
                Text("\(chapters) chapters")
                    .font(.asterionMono(9))
                    .foregroundStyle(Color.asterionBorderHover)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.asterionCard)
                .stroke(Color.asterionBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let status: String

    private var pillColor: Color {
        switch status.uppercased() {
        case "ONGOING":   return Color(red: 0.353, green: 0.608, blue: 0.478)
        case "COMPLETED": return Color(red: 0.545, green: 0.482, blue: 0.42)
        case "HIATUS":    return .orange
        default:          return Color.asterionDim
        }
    }

    var body: some View {
        Text(status)
            .font(.asterionMono(9))
            .foregroundStyle(pillColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(
                Capsule().stroke(pillColor.opacity(0.4), lineWidth: 1)
            )
    }
}
