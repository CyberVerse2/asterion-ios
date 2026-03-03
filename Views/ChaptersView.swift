import Inject
import SwiftUI

struct ChaptersView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @EnvironmentObject private var tabBarState: TabBarState
    @Environment(\.dismiss) private var dismiss
    let novel: Novel
    let allChapters: [Chapter]
    let totalCount: Int

    @State private var chapters: [Chapter] = []
    @State private var loading = false
    @State private var error: String?
    @State private var page = 0
    @State private var search = ""
    @State private var debouncedSearch = ""

    private let perPage = 30
    private var totalPages: Int { max(1, Int(ceil(Double(totalCount) / Double(perPage)))) }
    private var genreColor: Color { GenreStyle.color(for: novel.genres) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                chaptersHeader
                searchSection
                paginationHeader
                chapterList
                paginationFooter
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
        .task { await loadChapters(pg: 0) }
        .onAppear { tabBarState.isVisible = false }
        .debounceSearch(text: $search, debouncedText: $debouncedSearch)
        .onChange(of: debouncedSearch) { _, _ in
            page = 0
            Task { await loadChapters(pg: 0, searchTerm: debouncedSearch) }
        }
        .onChange(of: page) { _, newPage in
            Task { await loadChapters(pg: newPage, searchTerm: debouncedSearch) }
        }
        .enableInjection()
    }

    private var chaptersHeader: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [genreColor.opacity(0.05), Color.asterionBackground],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(novel.title)
                    .font(.asterionSerif(22))
                    .foregroundStyle(Color.asterionText)

                Text(totalCount > 0 ? "\(totalCount) chapters" : "Chapters")
                    .font(.asterionMono(11))
                    .foregroundStyle(Color.asterionDim)
            }
            .padding(.horizontal, 24)
            .padding(.top, 88)
            .padding(.bottom, 20)
        }
    }

    private var searchSection: some View {
        SearchInputView(text: $search, placeholder: "Search chapters by title or number...")
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
    }

    @ViewBuilder
    private var paginationHeader: some View {
        if totalPages > 1 {
            HStack {
                Text("Page \(page + 1) of \(totalPages)")
                    .font(.asterionMono(10))
                    .foregroundStyle(Color.asterionDim)

                Spacer()

                HStack(spacing: 8) {
                    Button { page = max(0, page - 1) } label: {
                        Text("◂")
                            .font(.system(size: 12))
                            .foregroundStyle(page == 0 ? Color.asterionCard : Color.asterionMuted)
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.asterionBorder, lineWidth: 1))
                    }
                    .disabled(page == 0)

                    Button { page = min(totalPages - 1, page + 1) } label: {
                        Text("▸")
                            .font(.system(size: 12))
                            .foregroundStyle(page >= totalPages - 1 ? Color.asterionCard : Color.asterionMuted)
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.asterionBorder, lineWidth: 1))
                    }
                    .disabled(page >= totalPages - 1)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var chapterList: some View {
        if loading {
            HStack {
                Spacer()
                ProgressView().tint(Color.goldAccent)
                Spacer()
            }
            .padding(.vertical, 40)
        } else if let error {
            VStack(spacing: 12) {
                Text(error)
                    .font(.asterionMono(13))
                    .foregroundStyle(Color.asterionMuted)
                Button("Try Again") {
                    Task { await loadChapters(pg: page, searchTerm: debouncedSearch) }
                }
                .font(.asterionMono(12))
                .foregroundStyle(Color.goldAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if chapters.isEmpty {
            Text(debouncedSearch.isEmpty ? "No chapters found" : "No chapters match your search")
                .font(.asterionMono(13))
                .foregroundStyle(Color.asterionDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    NavigationLink {
                        ReaderView(
                            initialChapter: chapter,
                            novel: novel,
                            allChapters: allChapters.isEmpty ? chapters : allChapters
                        )
                    } label: {
                        HStack(spacing: 10) {
                            Text("#\(chapter.chapterNumber)")
                                .font(.asterionMono(10))
                                .foregroundStyle(Color.asterionDim)
                                .frame(width: 40, alignment: .leading)

                            Text(chapter.title)
                                .font(.asterionSerif(15))
                                .foregroundStyle(Color.asterionReaderText)
                                .lineLimit(1)

                            Spacer()

                            Text("›")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.asterionBorder)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)

                    if index < chapters.count - 1 {
                        Divider().overlay(Color.asterionCard)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.asterionBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if totalPages > 1 && !loading && !chapters.isEmpty {
            HStack(spacing: 8) {
                Button {
                    page = max(0, page - 1)
                } label: {
                    Text("← Previous")
                        .font(.asterionMono(12))
                        .foregroundStyle(page == 0 ? Color.asterionBorder : Color.asterionMuted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.asterionBorder, lineWidth: 1))
                }
                .disabled(page == 0)

                Button {
                    page = min(totalPages - 1, page + 1)
                } label: {
                    Text("Next →")
                        .font(.asterionMono(12))
                        .foregroundStyle(page >= totalPages - 1 ? Color.asterionBorder : Color.goldAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(page >= totalPages - 1 ? .clear : genreColor.opacity(0.06))
                                .stroke(page >= totalPages - 1 ? Color.asterionBorder : genreColor.opacity(0.3), lineWidth: 1)
                        )
                }
                .disabled(page >= totalPages - 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private func loadChapters(pg: Int, searchTerm: String = "") async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let response = try await apiClient.fetchChapters(
                novelId: novel.id,
                limit: perPage,
                offset: pg * perPage
            )
            if searchTerm.isEmpty {
                chapters = response.data
            } else {
                let q = searchTerm.lowercased()
                chapters = response.data.filter {
                    $0.title.lowercased().contains(q) || String($0.chapterNumber).contains(q)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
