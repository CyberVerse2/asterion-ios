import AsterionKit
import SwiftUI

struct DownloadedNovelView: View {
    let collection: DownloadedNovelCollection
    @EnvironmentObject private var readingProgressService: ReadingProgressService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var chapters: [Chapter] = []

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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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

                VStack(alignment: .leading, spacing: 14) {
                    AsterionSectionLabel(title: "Chapters", detail: "\(chapters.count)")

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                            NavigationLink {
                                reader(chapter, resume: false)
                            } label: {
                                chapterRow(chapter, isCurrent: chapter.id == resumeChapter?.id, showsSeparator: index < chapters.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .asterionPanel(cornerRadius: 16)
                }
            }
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
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
        }
        .task {
            chapters = collection.chapters.map(\.chapter)
        }
    }

    private func chapterRow(_ chapter: Chapter, isCurrent: Bool, showsSeparator: Bool) -> some View {
        HStack(spacing: 12) {
            Text(chapter.chapterNumber > 0 ? "\(chapter.chapterNumber)" : "—")
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

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.asterionFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Color.asterionHairline)
                    .frame(height: 1)
                    .padding(.leading, 16 + 44 + 12)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(chapter.labeledTitle)
    }

    private func reader(_ chapter: Chapter, resume: Bool) -> some View {
        ReaderView(initialChapter: chapter, novel: collection.novel, allChapters: chapters,
                   shouldAutoResumeFromSavedProgress: resume, offlineOnly: true,
                   offlineChapterFiles: collection.chapters)
    }
}
