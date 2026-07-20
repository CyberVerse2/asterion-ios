import SwiftUI

enum UnifiedActivityMode {
    case continueActivity
    case history

    var title: String {
        switch self {
        case .continueActivity: "Continue"
        case .history: "History"
        }
    }

    var subtitle: String {
        switch self {
        case .continueActivity: "Pick up every story and screen from one place."
        case .history: "Your recent reading and watching activity."
        }
    }
}

struct UnifiedActivityView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    let mode: UnifiedActivityMode
    let query: String
    let selectReading: (AppModel.ContinueReadingEntry) -> Void
    let selectProgress: (MediaPlaybackProgress) -> Void
    let selectHistory: (MediaHistoryEntry) -> Void

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var items: [UnifiedActivityItem] {
        let reading = model.continueReadingEntries.map(UnifiedActivityItem.reading)
        let media: [UnifiedActivityItem] = switch mode {
        case .continueActivity:
            model.continueWatching.map(UnifiedActivityItem.progress)
        case .history:
            model.mediaHistory.map(UnifiedActivityItem.history)
        }
        return (reading + media)
            .filter { normalizedQuery.isEmpty || $0.matches(normalizedQuery) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    mode == .continueActivity ? "Nothing in progress" : "No history yet",
                    systemImage: mode == .continueActivity ? "play.circle" : "clock.arrow.circlepath",
                    description: Text(
                        normalizedQuery.isEmpty
                            ? "Your reading and watching activity will appear here."
                            : "No activity matches your search."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title)
                                .font(.asterionDisplay(28, weight: .semibold))
                            Text(mode.subtitle)
                                .font(.callout)
                                .foregroundStyle(Color.asterionMuted)
                        }
                        .padding(.bottom, 8)

                        ForEach(items) { item in
                            UnifiedActivityRow(
                                item: item,
                                select: { select(item) },
                                resume: { resume(item) }
                            )
                        }
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 48)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .hidingScrollIndicators()
            }
        }
        .background(.background)
        .navigationTitle(mode.title)
    }

    private func select(_ item: UnifiedActivityItem) {
        switch item {
        case .reading(let entry): selectReading(entry)
        case .progress(let progress): selectProgress(progress)
        case .history(let history): selectHistory(history)
        }
    }

    private func resume(_ item: UnifiedActivityItem) {
        switch item {
        case .reading(let entry):
            openWindow(
                value: ReaderRoute(
                    novelID: entry.novel.id,
                    chapterID: entry.progress.chapterId
                )
            )
        case .progress(let progress):
            open(progress: progress)
        case .history(let history):
            open(
                mediaType: history.mediaType,
                contentID: history.contentId,
                title: history.title,
                unitID: history.unitId
            )
        }
    }

    private func open(progress: MediaPlaybackProgress) {
        open(
            mediaType: progress.mediaType,
            contentID: progress.contentId,
            title: progress.title,
            unitID: progress.unitId
        )
    }

    private func open(
        mediaType: MediaAccountType,
        contentID: String,
        title: String,
        unitID: String
    ) {
        switch mediaType {
        case .anime:
            openWindow(
                value: AnimePlayerRoute(
                    slug: contentID,
                    title: title,
                    initialEpisodeID: unitID
                )
            )
        case .movie:
            openWindow(
                value: MoviePlayerRoute(
                    slug: contentID,
                    title: title,
                    initialEpisodeID: unitID
                )
            )
        case .football:
            break
        }
    }
}

private enum UnifiedActivityItem: Identifiable {
    case reading(AppModel.ContinueReadingEntry)
    case progress(MediaPlaybackProgress)
    case history(MediaHistoryEntry)

    var id: String {
        switch self {
        case .reading(let entry): "reading:\(entry.id)"
        case .progress(let progress): "progress:\(progress.id)"
        case .history(let history): "history:\(history.id)"
        }
    }

    var title: String {
        switch self {
        case .reading(let entry): entry.novel.title
        case .progress(let progress): progress.title
        case .history(let history): history.title
        }
    }

    var subtitle: String {
        switch self {
        case .reading(let entry): "Chapter · \(Int(entry.progress.percentage.rounded()))%"
        case .progress(let progress):
            Self.playbackLabel(
                unitTitle: progress.unitTitle,
                seasonNumber: progress.seasonNumber,
                episodeNumber: progress.episodeNumber,
                fallback: progress.mediaType.title
            )
        case .history(let history):
            Self.playbackLabel(
                unitTitle: history.unitTitle,
                seasonNumber: history.seasonNumber,
                episodeNumber: history.episodeNumber,
                fallback: history.mediaType.title
            )
        }
    }

    var canResume: Bool {
        switch self {
        case .reading:
            true
        case .progress(let progress):
            progress.mediaType != .football
        case .history(let history):
            history.mediaType != .football
        }
    }

    var kind: String {
        switch self {
        case .reading: "Novel"
        case .progress(let progress): progress.mediaType.title
        case .history(let history): history.mediaType.title
        }
    }

    var imageURL: URL? {
        switch self {
        case .reading(let entry): entry.novel.imageURL.flatMap(URL.init(string:))
        case .progress(let progress): progress.imageURL
        case .history(let history): history.imageURL
        }
    }

    var percentage: Double {
        switch self {
        case .reading(let entry): entry.progress.percentage
        case .progress(let progress): progress.percentage
        case .history(let history): history.percentage
        }
    }

    var updatedAt: Date {
        switch self {
        case .reading(let entry): entry.progress.updatedAt ?? .distantPast
        case .progress(let progress): progress.updatedAt
        case .history(let history): history.lastViewedAt
        }
    }

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || subtitle.localizedCaseInsensitiveContains(query)
            || kind.localizedCaseInsensitiveContains(query)
    }

    private static func playbackLabel(
        unitTitle: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        fallback: String
    ) -> String {
        let position: String? = if let seasonNumber, let episodeNumber {
            "S\(seasonNumber) E\(episodeNumber)"
        } else if let episodeNumber {
            "Episode \(episodeNumber)"
        } else {
            nil
        }

        if let position, let unitTitle, !unitTitle.isEmpty {
            return "\(position) · \(unitTitle)"
        }
        return position ?? unitTitle ?? fallback
    }
}

private struct UnifiedActivityRow: View {
    let item: UnifiedActivityItem
    let select: () -> Void
    let resume: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: select) {
                HStack(spacing: 16) {
                    MediaCoverView(url: item.imageURL, width: 70, height: 98)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.kind.uppercased())
                            .font(.asterionMono(9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Color.asterionAccent)
                        Text(item.title)
                            .font(.asterionDisplay(17, weight: .semibold))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(2)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.asterionMuted)
                            .lineLimit(1)
                        ProgressView(value: min(100, max(0, item.percentage)), total: 100)
                            .tint(Color.asterionAccent)
                            .frame(maxWidth: 320)
                    }

                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.canResume {
                Button(action: resume) {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .tint(.asterionAccent)
            }
        }
        .padding(14)
        .background(Color.asterionCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.08))
        }
        .asterionHoverLift()
    }
}
