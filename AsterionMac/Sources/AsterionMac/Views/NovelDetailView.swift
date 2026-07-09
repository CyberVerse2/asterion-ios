import SwiftUI

struct NovelDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let novel: Novel

    @State private var chapters: [Chapter] = []
    @State private var progress: ReadingProgress?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scrollPosition: String?
    @State private var showsFullSynopsis = false

    private var isInLibrary: Bool {
        model.libraryNovelIDs.contains(novel.id)
    }

    private var visibleChapters: [Chapter] {
        Array(chapters.suffix(5).reversed())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                hero
                    .id("detail-top")
                actions
                Divider().overlay(Color.asterionBorder)

                if !cleanSummary.isEmpty {
                    detailSection(title: "Synopsis") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(showsFullSynopsis ? cleanSummary : synopsisPreview)
                                .font(.asterionReading(15))
                                .foregroundStyle(Color.asterionReaderText)
                                .lineSpacing(5)
                                .textSelection(.enabled)

                            if synopsisPreview != cleanSummary {
                                Button {
                                    showsFullSynopsis.toggle()
                                } label: {
                                    Label(
                                        showsFullSynopsis ? "Show less" : "Read full synopsis",
                                        systemImage: showsFullSynopsis ? "chevron.up" : "chevron.down"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.asterionAccent)
                                }
                                .buttonStyle(AsterionPressButtonStyle())
                            }
                        }
                    }
                }

                Divider().overlay(Color.asterionBorder)

                detailSection(title: "Chapters", trailing: chapterCountLabel) {
                    chapterList
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 28)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .hidingScrollIndicators()
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .background(Color.asterionSurface)
        .navigationTitle(novel.title)
        .safeAreaInset(edge: .bottom) { accountErrorBar }
        .task(id: novel.id) {
            showsFullSynopsis = false
            scrollPosition = nil
            await load()
            await Task.yield()
            scrollPosition = "detail-top"
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 24) {
            CoverView(novel: novel, width: 156, height: 224)

            VStack(alignment: .leading, spacing: 13) {
                Text(novel.title)
                    .font(.asterionDisplay(28, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                Text(novel.authorDisplayName)
                    .font(.asterionDisplay(16, weight: .medium))
                    .foregroundStyle(Color.asterionText)

                VStack(alignment: .leading, spacing: 9) {
                    MetadataLine(
                        icon: "book.closed",
                        value: novel.genres?.first ?? "Fiction"
                    )
                    MetadataLine(
                        icon: "text.page",
                        value: "\(novel.totalChapters ?? String(chapters.count)) chapters"
                    )
                    MetadataLine(icon: "eye", value: "\(novel.views ?? "—") views")
                    MetadataLine(
                        icon: "star",
                        value: novel.rating.map { String(format: "%.1f rating", $0) } ?? "Not yet rated"
                    )
                }
                .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    openPreferredChapter()
                } label: {
                    Label(readButtonTitle, systemImage: "book.pages")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(Color.asterionAccent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(AsterionPressButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(chapters.isEmpty)

                Button {
                    Task { await model.toggleLibrary(novelID: novel.id) }
                } label: {
                    Label {
                        Text(isInLibrary ? "Saved" : "Save")
                    } icon: {
                        Image(systemName: isInLibrary ? "bookmark.fill" : "bookmark")
                            .contentTransition(.symbolEffect(.replace))
                    }
                        .frame(minWidth: 76)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.asterionText)
                        .background(Color.asterionSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.asterionBorder)
                        }
                }
                .buttonStyle(AsterionPressButtonStyle())
                .disabled(!model.isSignedIn || model.isUpdatingLibrary)
                .animation(reduceMotion ? nil : AsterionMotion.hover, value: isInLibrary)
            }

            if let progress {
                HStack(spacing: 10) {
                    ProgressView(value: min(1, max(0, progress.percentage / 100)))
                        .tint(Color.asterionAccent)
                        .animation(reduceMotion ? nil : AsterionMotion.reveal, value: progress.percentage)
                    Text("\(Int(progress.percentage))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.asterionMuted)
                }
            }
        }
    }

    @ViewBuilder
    private var chapterList: some View {
        if isLoading {
            ProgressView("Loading chapters…")
                .frame(maxWidth: .infinity, minHeight: 100)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Chapters unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        } else if chapters.isEmpty {
            ContentUnavailableView("No chapters", systemImage: "text.page")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(visibleChapters) { chapter in
                    Button {
                        open(chapter)
                    } label: {
                        HStack(spacing: 14) {
                            Text(String(chapter.chapterNumber))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Color.asterionMuted)
                                .frame(width: 34, alignment: .trailing)
                            Text(chapter.title)
                                .font(.asterionDisplay(14, weight: .medium))
                                .foregroundStyle(Color.asterionText)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(Color.asterionMuted)
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(AsterionPressButtonStyle())
                    Divider().overlay(Color.asterionBorder)
                }
            }
        }
    }

    @ViewBuilder
    private var accountErrorBar: some View {
        if let error = model.accountError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(Color.asterionAccent)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
        }
    }

    private var cleanSummary: String {
        let cleaned = (novel.summary ?? "")
            .replacingOccurrences(of: "Show More", with: "")
            .replacingOccurrences(
                of: "\\s+on [A-Z][a-z]+ \\d{1,2}, \\d{4}.*$",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "([.!?])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private var synopsisPreview: String {
        guard cleanSummary.count > 280 else { return cleanSummary }
        let prefix = String(cleanSummary.prefix(280))
        if let sentenceEnd = prefix.lastIndex(where: { ".!?".contains($0) }) {
            return String(prefix[...sentenceEnd])
        }
        if let wordBoundary = prefix.lastIndex(where: { $0.isWhitespace }) {
            return String(prefix[..<wordBoundary]) + "…"
        }
        return prefix + "…"
    }

    private var readButtonTitle: String {
        guard let progress else { return "Start Reading" }
        guard let chapter = chapters.first(where: { $0.id == progress.chapterId }) else {
            return "Continue Reading"
        }
        return "Continue Reading · Chapter \(chapter.chapterNumber)"
    }

    private var chapterCountLabel: String? {
        chapters.isEmpty ? nil : "\(chapters.count) chapters"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let chapterRequest = model.chapters(for: novel.id)
            async let progressRequest = model.fetchProgress(novelID: novel.id)
            chapters = try await chapterRequest
            progress = try await progressRequest
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openPreferredChapter() {
        let preferred = progress.flatMap { saved in
            chapters.first { $0.id == saved.chapterId }
        } ?? chapters.first
        if let preferred { open(preferred) }
    }

    private func open(_ chapter: Chapter) {
        openWindow(value: ReaderRoute(novelID: novel.id, chapterID: chapter.id))
    }

    private func detailSection<Content: View>(
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.asterionDisplay(20, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(Color.asterionAccent)
                }
            }
            content()
        }
    }
}

private struct MetadataLine: View {
    let icon: String
    let value: String

    var body: some View {
        Label {
            Text(value)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .frame(width: 16)
        }
        .font(.caption)
        .foregroundStyle(Color.asterionMuted)
    }
}
