import SwiftUI

struct NovelDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let novel: Novel

    @State private var chapters: [Chapter] = []
    @State private var progress: ReadingProgress?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isInLibrary: Bool {
        model.libraryNovelIDs.contains(novel.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                metadata

                if let summary = novel.summary, !summary.isEmpty {
                    section(title: "Synopsis") {
                        Text(summary)
                            .font(.asterionSerif(16))
                            .foregroundStyle(Color.asterionReaderText)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                    }
                }

                section(title: "Chapters") {
                    chapterList
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .background(Color.asterionBackground)
        .navigationTitle(novel.title)
        .safeAreaInset(edge: .bottom) {
            if let error = model.accountError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.toggleLibrary(novelID: novel.id) }
                } label: {
                    Label(
                        isInLibrary ? "Remove from Library" : "Add to Library",
                        systemImage: isInLibrary ? "books.vertical.fill" : "books.vertical"
                    )
                }
                .disabled(!model.isSignedIn || model.isUpdatingLibrary)

                Button("Read", systemImage: "book.pages") {
                    openPreferredChapter()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(chapters.isEmpty)
            }
        }
        .task(id: novel.id) { await load() }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 28) {
            CoverView(novel: novel, width: 170, height: 238)

            VStack(alignment: .leading, spacing: 14) {
                Text(novel.title)
                    .font(.asterionSerif(34, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .textSelection(.enabled)

                Text(novel.authorDisplayName)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let genres = novel.genres, !genres.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 7) {
                            ForEach(genres, id: \.self) { genre in
                                Text(genre.uppercased())
                                    .font(.asterionMono(10, weight: .medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(GenreStyle.color(for: [genre]).opacity(0.2), in: Capsule())
                                    .foregroundStyle(Color.asterionText)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }

                HStack(spacing: 12) {
                    Button {
                        openPreferredChapter()
                    } label: {
                        Label(readButtonTitle, systemImage: "book.pages.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.asterionGold)
                    .disabled(chapters.isEmpty)

                    Button {
                        Task { await model.toggleLibrary(novelID: novel.id) }
                    } label: {
                        Label(isInLibrary ? "Saved" : "Save", systemImage: isInLibrary ? "checkmark" : "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.isSignedIn || model.isUpdatingLibrary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metadata: some View {
        HStack(spacing: 0) {
            Metric(value: novel.rating.map { String(format: "%.1f", $0) } ?? "—", label: "Rating")
            Divider().frame(height: 38)
            Metric(value: novel.totalChapters ?? String(chapters.count), label: "Chapters")
            Divider().frame(height: 38)
            Metric(value: novel.views ?? "—", label: "Views")
            Divider().frame(height: 38)
            Metric(value: novel.status ?? "Unknown", label: "Status")
        }
        .padding(.vertical, 16)
        .background(Color.asterionCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.asterionBorder)
        }
    }

    @ViewBuilder
    private var chapterList: some View {
        if isLoading {
            ProgressView("Loading chapters…")
                .frame(maxWidth: .infinity, minHeight: 120)
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
                ForEach(chapters.prefix(40)) { chapter in
                    Button {
                        open(chapter)
                    } label: {
                        HStack {
                            Text(String(chapter.chapterNumber))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                            Text(chapter.title)
                                .foregroundStyle(Color.asterionText)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Color.asterionBorder)
                }
            }
            .padding(.horizontal, 14)
            .background(Color.asterionCard.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))

            if chapters.count > 40 {
                Text("Showing the first 40 of \(chapters.count) chapters. Open the reader to continue through the full list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readButtonTitle: String {
        progress == nil ? "Start Reading" : "Continue Reading"
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
        let preferred = progress.flatMap { saved in chapters.first { $0.id == saved.chapterId } } ?? chapters.first
        if let preferred { open(preferred) }
    }

    private func open(_ chapter: Chapter) {
        openWindow(value: ReaderRoute(novelID: novel.id, chapterID: chapter.id))
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.asterionSerif(22, weight: .semibold))
                .foregroundStyle(Color.asterionText)
            content()
        }
    }
}

private struct Metric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.asterionText)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
