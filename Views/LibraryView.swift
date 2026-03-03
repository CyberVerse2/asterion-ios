import Inject
import SwiftUI

struct LibraryView: View {
    @ObserveInjection var inject
    @EnvironmentObject private var apiClient: APIClient
    @State private var novels: [Novel] = []
    @State private var loading = false
    @State private var failed = false
    @State private var search = ""
    @State private var debouncedSearch = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SearchInputView(text: $search, placeholder: "Search by title or author...")
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

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
                            Text("Couldn't load library")
                                .font(.asterionMono(13))
                                .foregroundStyle(Color.asterionMuted)
                            Button {
                                Task { await loadNovels(search: debouncedSearch) }
                            } label: {
                                Text("Try Again")
                                    .font(.asterionMono(13))
                                    .foregroundStyle(Color.goldAccent)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if novels.isEmpty {
                        VStack(spacing: 12) {
                            Text("📚").font(.system(size: 36)).opacity(0.3)
                            Text(debouncedSearch.isEmpty ? "Library is empty" : "No results")
                                .font(.asterionMono(13))
                                .foregroundStyle(Color.asterionDim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(novels.enumerated()), id: \.element.id) { index, novel in
                                NavigationLink(value: novel) {
                                    LibraryRow(novel: novel)
                                }
                                .buttonStyle(.plain)

                                Divider().overlay(Color.asterionCard)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await loadNovels(search: debouncedSearch) }
            .background(Color.asterionBackground.ignoresSafeArea())
            .navigationTitle("Library")
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

    private func loadNovels(search: String = "") async {
        loading = true
        defer { loading = false }
        do {
            novels = try await apiClient.fetchNovels(limit: 100, search: search)
            failed = false
        } catch {
            if novels.isEmpty { failed = true }
        }
    }
}

// MARK: - Library Row

private struct LibraryRow: View {
    let novel: Novel

    var body: some View {
        HStack(spacing: 16) {
            CoverImageView(novel: novel, size: .sm)

            VStack(alignment: .leading, spacing: 3) {
                Text(novel.title)
                    .font(.asterionSerif(16, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text(novel.author ?? "Unknown")
                        .font(.asterionMono(11))
                        .foregroundStyle(Color.asterionMuted)
                    if let genre = novel.genres?.first {
                        Text(" · \(genre)")
                            .font(.asterionMono(11))
                            .foregroundStyle(Color.asterionMuted)
                    }
                }

                HStack(spacing: 8) {
                    if let rating = novel.rating {
                        Text("★ \(String(format: "%.1f", rating))")
                            .font(.asterionMono(10))
                            .foregroundStyle(Color.goldAccent)
                    }
                    if let status = novel.status {
                        Text(status)
                            .font(.asterionMono(9))
                            .foregroundStyle(Color.asterionDim)
                    }
                }
                .padding(.top, 3)
            }

            Spacer(minLength: 0)

            Text("›")
                .font(.system(size: 16))
                .foregroundStyle(Color.asterionBorder)
        }
        .padding(.vertical, 16)
    }
}
