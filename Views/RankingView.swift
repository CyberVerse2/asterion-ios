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
    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    private var contentMaxWidth: CGFloat { isDesktop ? 1120 : .infinity }
    private var pageHorizontalPadding: CGFloat { isDesktop ? 46 : 24 }

    enum SortOption: String, CaseIterable {
        case rank = "By Rank"
        case rating = "By Rating"
        case views = "By Views"
    }

    private var sorted: [Novel] {
        switch sortBy {
        case .rank:
            return novels.sorted {
                parsedInteger($0.rank, fallback: Int.max) < parsedInteger($1.rank, fallback: Int.max)
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
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .refreshable { await loadNovels() }
            .background(Color.asterionBackground.ignoresSafeArea())
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

    // MARK: - Sort Pills

    private var pageTitleSection: some View {
        Text("Rankings")
            .font(.asterionSerif(isDesktop ? 58 : 42, weight: .semibold))
            .foregroundStyle(Color.asterionText)
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, isDesktop ? 26 : 14)
            .padding(.bottom, isDesktop ? 16 : 6)
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
            .padding(.horizontal, pageHorizontalPadding)
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
                        rankLabel: rankLabel(for: novel, position: index + 1)
                    )
                }
                .buttonStyle(.plain)

                if index < sorted.count - 1 {
                    Divider().overlay(Color.asterionCard)
                }
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
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

    private func rankLabel(for novel: Novel, position: Int) -> String {
        if sortBy == .rank, let rank = novel.rank, parsedInteger(rank, fallback: Int.max) != Int.max {
            return "#\(parsedInteger(rank, fallback: position))"
        }
        return "\(position)"
    }
}

// MARK: - Ranking Row

private struct RankingRow: View {
    let novel: Novel
    let rankLabel: String

    var body: some View {
        HStack(spacing: 14) {
            Text(rankLabel)
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
