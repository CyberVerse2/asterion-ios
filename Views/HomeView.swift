import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var novels: [Novel] = []
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.asterionBackground.ignoresSafeArea()
                List(novels) { novel in
                    NavigationLink(value: novel) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(novel.title)
                                .font(.headline)
                                .foregroundStyle(Color.asterionText)
                            Text(novel.author ?? "Unknown author")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.asterionCard)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .navigationTitle("Asterion")
                .navigationDestination(for: Novel.self) { novel in
                    NovelDetailView(novel: novel)
                }
                .overlay {
                    if loading {
                        ProgressView().tint(Color.goldAccent)
                    }
                }
            }
            .task {
                loading = true
                defer { loading = false }
                novels = (try? await apiClient.fetchNovels()) ?? []
            }
        }
    }
}
