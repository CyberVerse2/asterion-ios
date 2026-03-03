import Inject
import SwiftUI

struct RankingView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @State private var novels: [Novel] = []
    @State private var loading = false
    @State private var failed = false
    @State private var sortBy: SortOption = .rank

    enum SortOption: String, CaseIterable {
        case rank = "By Rank"
        case rating = "By Rating"
        case views = "By Views"
    }

    private var sorted: [Novel] {
        switch sortBy {
        case .rank:
            return novels.sorted {
                (Int($0.rank ?? "") ?? 9999) < (Int($1.rank ?? "") ?? 9999)
            }
        case .rating:
            return novels.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .views:
            return novels.sorted {
                parseViews($0.views) > parseViews($1.views)
            }
        }
    }

    private func parseViews(_ v: String?) -> Int {
        guard let v else { return 0 }
        return Int(v.filter(\.isNumber)) ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pageTitleSection
                    sortPillsSection

                    if loading && novels.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView().tint(Color.goldAccent).scaleEffect(1.2)
                            Spacer()
                        }
                        .padding(40)
                    } else if failed && novels.isEmpty {
                        VStack(spacing: 12) {
                            Text("⚠").font(.system(size: 32)).opacity(0.4)
                            Text("Couldn't load rankings")
                                .font(.asterionMono(13))
                                .foregroundStyle(Color.asterionMuted)
                            Button {
                                Task { await loadNovels() }
                            } label: {
                                Text("Try Again")
                                    .font(.asterionMono(13))
                                    .foregroundStyle(Color.goldAccent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else if sorted.isEmpty {
                        Text("No novels found")
                            .font(.asterionMono(13))
                            .foregroundStyle(Color.asterionDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                    } else {
                        rankingList
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await loadNovels() }
            .background(Color.asterionBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Novel.self) { novel in
                NovelDetailView(novel: novel)
            }
            .task { await loadNovels() }
        }
        .enableInjection()
    }

    // MARK: - Sort Pills

    private var pageTitleSection: some View {
        Text("Rankings")
            .font(.asterionSerif(42, weight: .semibold))
            .foregroundStyle(Color.asterionText)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private var sortPillsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { sortBy = option }
                    } label: {
                        Text(option.rawValue)
                            .font(.asterionMono(12))
                            .foregroundStyle(sortBy == option ? Color.goldAccent : Color.asterionMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(sortBy == option ? Color.goldAccent.opacity(0.07) : .clear)
                                    .stroke(
                                        sortBy == option ? Color.goldAccent.opacity(0.5) : Color.asterionBorder,
                                        lineWidth: 1
                                    )
                            )
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    // MARK: - Ranking List

    private var rankingList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, novel in
                NavigationLink(value: novel) {
                    RankingRow(
                        novel: novel,
                        rank: index + 1
                    )
                }
                .buttonStyle(.plain)

                if index < sorted.count - 1 {
                    Divider().overlay(Color.asterionCard)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Data

    private func loadNovels() async {
        loading = true
        defer { loading = false }
        do {
            novels = try await apiClient.fetchNovels(limit: 100)
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
}

// MARK: - Ranking Row

private struct RankingRow: View {
    let novel: Novel
    let rank: Int

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.asterionMono(11))
                .foregroundStyle(Color.asterionBorderHover)
                .frame(width: 36)

            CoverImageView(novel: novel, size: .sm)

            VStack(alignment: .leading, spacing: 3) {
                Text(novel.title)
                    .font(.asterionSerif(15, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)

                Text(novel.author ?? "Unknown")
                    .font(.asterionMono(11))
                    .foregroundStyle(Color.asterionMuted)

                HStack(spacing: 10) {
                    if let rating = novel.rating {
                        Text("★ \(String(format: "%.1f", rating))")
                            .font(.asterionMono(11))
                            .foregroundStyle(Color.goldAccent)
                    }
                    if let views = novel.views {
                        Text("\(views) views")
                            .font(.asterionMono(10))
                            .foregroundStyle(Color.asterionDim)
                    }
                    if let status = novel.status {
                        StatusPill(status: status)
                    }
                }
                .padding(.top, 3)
            }

            Spacer(minLength: 0)

            Text("›")
                .font(.system(size: 16))
                .foregroundStyle(Color.asterionBorder)
        }
        .padding(.vertical, 14)
    }
}
