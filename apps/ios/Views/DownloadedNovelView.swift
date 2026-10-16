import AsterionKit
import SwiftUI

struct DownloadedNovelView: View {
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var collection: DownloadedNovelCollection
    @State private var confirmsRemoval = false
    @State private var isRemoving = false

    init(collection: DownloadedNovelCollection) {
        _collection = State(initialValue: collection)
    }

    private var chapters: [Chapter] { collection.chapters.map(\.chapter) }

    private var resumeChapter: Chapter? {
        let saved = readingProgressService.localProgress.first { $0.novelId == collection.novel.id }
        return chapters.first { $0.id == saved?.chapterId } ?? chapters.first
    }

    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }

    private var subtitle: String {
        let count = chapters.count
        return "\(count) \(count == 1 ? "chapter" : "chapters") available offline · \(collection.formattedSize)"
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 12, leading: pageHorizontalPadding, bottom: 8, trailing: pageHorizontalPadding))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(collection.chapters) { file in
                    NavigationLink {
                        reader(file.chapter, resume: false)
                    } label: {
                        chapterRow(file.chapter, isCurrent: file.id == resumeChapter?.id)
                    }
                    .listRowBackground(Color.asterionSurface)
                    .listRowSeparatorTint(Color.asterionHairline)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await remove([file]) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                AsterionSectionLabel(title: "Chapters", detail: String(chapters.count))
                    .textCase(nil)
                    .padding(.bottom, 6)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                AsterionBackdrop()
                ArtworkGlow(url: collection.novel.imageUrl.flatMap(URL.init(string:)), height: 460, intensity: 0.6)
                    .ignoresSafeArea()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Downloads")
                    .font(.asterionTitle(15, weight: .bold))
                    .foregroundStyle(Color.asterionText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    confirmsRemoval = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isRemoving)
                .accessibilityLabel("Remove download")
            }
        }
        .confirmationDialog(
            "Remove \(collection.title) from this device?",
            isPresented: $confirmsRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove download", role: .destructive) {
                Task { await removeNovel() }
            }
        } message: {
            Text("All \(chapters.count) downloaded chapters are deleted. Reading progress is kept.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom, spacing: 16) {
                NovelPosterArt(novel: collection.novel)
                    .frame(width: 84, height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.asterionBorder)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                    .accessibilityHidden(true)

                AsterionPageHeader(title: collection.title, subtitle: subtitle)
            }

            if let resumeChapter {
                NavigationLink {
                    reader(resumeChapter, resume: true)
                } label: {
                    AsterionPrimaryActionLabel(title: "Continue reading")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chapterRow(_ chapter: Chapter, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: chapter.chapterNumber > 0 ? String(chapter.chapterNumber) : "—")
                .font(.asterionMono(12, weight: .medium))
                .foregroundStyle(isCurrent ? Color.asterionText : Color.asterionFaint)
                .frame(width: 44, alignment: .leading)

            Text(chapter.displayTitle.isEmpty ? chapter.labeledTitle : chapter.displayTitle)
                .font(.asterionReading(14.5, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(Color.asterionText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 8)

            if isCurrent {
                AsterionEyebrow(text: "Last read", color: .asterionMuted)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chapter.labeledTitle)
    }

    private func reader(_ chapter: Chapter, resume: Bool) -> some View {
        ReaderView(initialChapter: chapter, novel: collection.novel, allChapters: chapters,
                   shouldAutoResumeFromSavedProgress: resume, offlineOnly: true,
                   offlineChapterFiles: collection.chapters)
    }

    /// Deletes the swiped chapters; deleting the last one removes the novel.
    private func remove(_ files: [DownloadedChapterFile]) async {
        if let updated = await OfflineChapterStore.shared.removeDownloadedChapters(files, from: collection) {
            collection = updated
            Haptics.tap()
        } else {
            Haptics.tap()
            dismiss()
        }
    }

    private func removeNovel() async {
        isRemoving = true
        await NovelDownloadManager.shared.cancelAndWait(novelID: collection.novel.id)
        await OfflineChapterStore.shared.removeDownloadedNovel(collection)
        Haptics.tap()
        dismiss()
    }
}
