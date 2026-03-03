import SwiftUI

struct NovelDetailView: View {
    @EnvironmentObject private var apiClient: APIClient
    let novel: Novel
    @State private var chapters: [Chapter] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(novel.title)
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.asterionText)

                Text(novel.summary ?? "No synopsis available.")
                    .foregroundStyle(Color.asterionText.opacity(0.85))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Chapters")
                        .font(.headline)
                        .foregroundStyle(Color.goldAccent)

                    ForEach(chapters) { chapter in
                        NavigationLink {
                            ReaderView(chapter: chapter, novelTitle: novel.title)
                        } label: {
                            HStack {
                                Text("Chapter \(chapter.chapterNumber)")
                                Spacer()
                                Text(chapter.title)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.asterionBackground)
        .task {
            chapters = (try? await apiClient.fetchChapters(novelId: novel.id)) ?? []
        }
    }
}
