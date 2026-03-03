import SwiftUI

struct RankingView: View {
    @EnvironmentObject private var apiClient: APIClient
    @State private var novels: [Novel] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.asterionBackground.ignoresSafeArea()
                List(Array(novels.enumerated()), id: \.1.id) { idx, novel in
                    HStack(spacing: 12) {
                        Text("#\(idx + 1)")
                            .font(.headline)
                            .foregroundStyle(Color.goldAccent)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(novel.title).foregroundStyle(Color.asterionText)
                            Text(novel.author ?? "Unknown").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.asterionCard)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Ranking")
            .task {
                novels = (try? await apiClient.fetchNovels(limit: 50)) ?? []
            }
        }
    }
}
