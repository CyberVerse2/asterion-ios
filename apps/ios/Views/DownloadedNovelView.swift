import SwiftUI

struct DownloadedNovelView: View {
    let collection: DownloadedNovelCollection
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @State private var chapters: [Chapter] = []

    private var resumeChapter: Chapter? {
        let saved = readingProgressService.localProgress.first { $0.novelId == collection.novel.id }
        return chapters.first { $0.id == saved?.chapterId } ?? chapters.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AsterionPageHeader(title: collection.title)
                Text("\(chapters.count) chapters available offline")
                    .font(.asterionReading(14))
                    .foregroundStyle(Color.asterionMuted)
                if let resumeChapter {
                    NavigationLink {
                        reader(resumeChapter, resume: true)
                    } label: {
                        AsterionPrimaryActionLabel(title: "Continue reading")
                    }
                    .buttonStyle(.plain)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(chapters) { chapter in
                        NavigationLink {
                            reader(chapter, resume: false)
                        } label: {
                            HStack(spacing: 12) {
                                Text(chapter.labeledTitle)
                                    .font(.asterionReading(16))
                                    .foregroundStyle(Color.asterionText)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12))
                                    .foregroundStyle(Color.asterionMuted)
                            }
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background { AsterionBackdrop() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Downloads").font(.asterionDisplay(18, weight: .medium))
                    .foregroundStyle(Color.asterionText)
            }
        }
        .task {
            chapters = collection.chapters.map(\.chapter)
        }
    }

    private func reader(_ chapter: Chapter, resume: Bool) -> some View {
        ReaderView(initialChapter: chapter, novel: collection.novel, allChapters: chapters,
                   shouldAutoResumeFromSavedProgress: resume, offlineOnly: true,
                   offlineChapterFiles: collection.chapters)
    }
}
