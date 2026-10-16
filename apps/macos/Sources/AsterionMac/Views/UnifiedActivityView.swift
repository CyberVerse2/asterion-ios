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

    @State private var filter: ActivityFilter = .all

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var items: [UnifiedActivityItem] {
        // Finished novels leave Continue, as finished shows do, but stay in History.
        let readingEntries = mode == .continueActivity
            ? model.continueReadingEntries
            : model.readingEntries
        let reading = readingEntries.map(UnifiedActivityItem.reading)
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

    private var filterOptions: [ActivityFilter] {
        let base: [ActivityFilter] = [.all, .novels, .anime, .films]
        return items.contains { $0.category == .football } ? base + [.football] : base
    }

    private var effectiveFilter: ActivityFilter {
        filterOptions.contains(filter) ? filter : .all
    }

    private var filteredItems: [UnifiedActivityItem] {
        let filter = effectiveFilter
        return filter == .all ? items : items.filter { $0.category == filter }
    }

    var body: some View {
        let allItems = items
        let visibleItems = filteredItems

        Group {
            if visibleItems.isEmpty {
                AsterionEmptyPage {
                    header(allItems)
                    emptyState(hasAnyItems: !allItems.isEmpty)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(allItems)
                        timeline(visibleItems)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .hidingScrollIndicators()
            }
        }
        .background(Color.asterionMediaCanvas)
    }

    // MARK: Header

    private func header(_ allItems: [UnifiedActivityItem]) -> some View {
        AsterionPageHeader(mode.title, subtitle: headerSubtitle(allItems)) {
            if !allItems.isEmpty {
                Picker("Show", selection: $filter) {
                    ForEach(filterOptions) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Filter by type")
            }
        }
    }

    private func headerSubtitle(_ allItems: [UnifiedActivityItem]) -> String {
        guard !allItems.isEmpty else { return mode.subtitle }
        switch mode {
        case .continueActivity:
            let reading = allItems.count(where: { $0.category == .novels })
            let watching = allItems.count - reading
            var parts = ["\(allItems.count) in progress"]
            if reading > 0 { parts.append("\(reading) reading") }
            if watching > 0 { parts.append("\(watching) watching") }
            return parts.joined(separator: " · ")
        case .history:
            let days = Set(allItems.map { item in
                item.updatedAt == .distantPast ? .distantPast : Calendar.current.startOfDay(for: item.updatedAt)
            }).count
            let entries = allItems.count == 1 ? "1 entry" : "\(allItems.count) entries"
            let span = days == 1 ? "1 day" : "\(days) days"
            return "\(entries) across \(span)"
        }
    }

    // MARK: Timeline

    private func timeline(_ visibleItems: [UnifiedActivityItem]) -> some View {
        let groups = ActivityDayGroup.groups(for: visibleItems)
        let leadID = mode == .continueActivity
            ? visibleItems.first(where: \.canResume)?.id
            : nil

        return LazyVStack(alignment: .leading, spacing: 32) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        AsterionEyebrow(text: group.title)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Text(group.items.count, format: .number)
                            .font(.asterionMono(11))
                            .foregroundStyle(Color.asterionFaint)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                ActivityRowSeparator()
                            }
                            ActivityTimelineRow(
                                imageURL: item.imageURL,
                                fallbackSystemImage: item.fallbackSystemImage,
                                title: item.title,
                                detail: item.detail,
                                timestamp: timestamp(for: item, in: group),
                                fraction: item.fraction,
                                actionTitle: item.actionTitle,
                                actionSystemImage: item.actionSystemImage,
                                isPrimaryAction: item.id == leadID,
                                canAct: item.canResume,
                                select: { select(item) },
                                action: { resume(item) }
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .asterionPanel(cornerRadius: 14)
                }
            }
        }
        .frame(maxWidth: 920, alignment: .leading)
        .padding(.horizontal, AsterionLayout.pageInset)
        .padding(.top, 30)
        .padding(.bottom, 56)
    }

    private func timestamp(for item: UnifiedActivityItem, in group: ActivityDayGroup) -> String? {
        guard item.updatedAt != .distantPast else { return nil }
        return item.updatedAt.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Empty

    @ViewBuilder
    private func emptyState(hasAnyItems: Bool) -> some View {
        if hasAnyItems {
            AsterionEmptyState(
                systemImage: "line.3.horizontal.decrease.circle",
                title: "Nothing in \(effectiveFilter.title.lowercased())",
                message: mode == .continueActivity
                    ? "Start something in \(effectiveFilter.title.lowercased()) and it will wait for you here."
                    : "Your \(effectiveFilter.title.lowercased()) activity will appear here."
            ) {
                Button("Show everything") { filter = .all }
                    .buttonStyle(.asterionSecondary)
            }
        } else if !normalizedQuery.isEmpty {
            AsterionEmptyState(
                systemImage: "magnifyingglass",
                title: "No matches",
                message: "Nothing in your activity matches “\(normalizedQuery)”. Try a different title or episode."
            )
        } else {
            AsterionEmptyState(
                systemImage: mode == .continueActivity ? "play.circle" : "clock.arrow.circlepath",
                title: mode == .continueActivity ? "Nothing in progress" : "No history yet",
                message: "Open a novel or start an episode. Your reading and watching activity will appear here."
            )
        }
    }

    // MARK: Actions

    private func select(_ item: UnifiedActivityItem) {
        switch item {
        case .reading(let entry): selectReading(entry)
        case .progress(let progress): selectProgress(progress)
        case .history(let history): selectHistory(history)
        }
    }

    private func resume(_ item: UnifiedActivityItem) {
        switch item {
        case .reading(let entry) where entry.novelProgress.isFinished:
            // Read again from the first chapter.
            Task {
                guard let first = try? await model.chapter(novelID: entry.novel.id, number: 1) else { return }
                openWindow(value: ReaderRoute(novelID: entry.novel.id, chapterID: first.id))
            }
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

// MARK: - Model

private enum ActivityFilter: String, CaseIterable, Identifiable {
    case all
    case novels
    case anime
    case films
    case football

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .novels: "Novels"
        case .anime: "Anime"
        case .films: "Films"
        case .football: "Football"
        }
    }

    init(_ mediaType: MediaAccountType) {
        switch mediaType {
        case .anime: self = .anime
        case .movie: self = .films
        case .football: self = .football
        }
    }
}

private struct ActivityDayGroup: Identifiable {
    let id: Date
    let title: String
    let items: [UnifiedActivityItem]

    static func groups(for items: [UnifiedActivityItem], now: Date = .now) -> [ActivityDayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [UnifiedActivityItem]] = [:]
        for item in items {
            let day = item.updatedAt == .distantPast ? .distantPast : calendar.startOfDay(for: item.updatedAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(item)
        }
        return order.map { day in
            ActivityDayGroup(id: day, title: title(for: day, now: now, calendar: calendar), items: buckets[day] ?? [])
        }
    }

    private static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        if day == .distantPast { return "Earlier" }
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let distance = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day,
           distance > 0, distance < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(day, equalTo: now, toGranularity: .year) {
            return day.formatted(.dateTime.day().month(.wide))
        }
        return day.formatted(.dateTime.day().month(.wide).year())
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

    var category: ActivityFilter {
        switch self {
        case .reading: .novels
        case .progress(let progress): ActivityFilter(progress.mediaType)
        case .history(let history): ActivityFilter(history.mediaType)
        }
    }

    /// "Ch. 1929 of 3171 · 61%" or "S1 E3 · 12 min left".
    var detail: String {
        switch self {
        case .reading(let entry):
            return ActivityDetail.reading(entry.novelProgress)
        case .progress(let progress):
            return ActivityDetail.playback(
                title: progress.title,
                unitTitle: progress.unitTitle,
                seasonNumber: progress.seasonNumber,
                episodeNumber: progress.episodeNumber,
                mediaType: progress.mediaType,
                positionSeconds: progress.positionSeconds,
                durationSeconds: progress.durationSeconds,
                completed: progress.completed
            )
        case .history(let history):
            return ActivityDetail.playback(
                title: history.title,
                unitTitle: history.unitTitle,
                seasonNumber: history.seasonNumber,
                episodeNumber: history.episodeNumber,
                mediaType: history.mediaType,
                positionSeconds: history.positionSeconds,
                durationSeconds: history.durationSeconds,
                completed: history.completed
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

    var fallbackSystemImage: String {
        switch self {
        case .reading: "book.closed"
        case .progress(let progress): progress.mediaType.systemImage
        case .history(let history): history.mediaType.systemImage
        }
    }

    var imageURL: URL? {
        switch self {
        case .reading(let entry): entry.novel.imageURL.flatMap(URL.init(string:))
        case .progress(let progress): progress.imageURL
        case .history(let history): history.imageURL
        }
    }

    /// Novels measure the whole novel, so their line waits for the chapter
    /// number rather than showing the in-chapter position.
    var fraction: Double? {
        switch self {
        case .reading(let entry): entry.novelProgress.fraction
        case .progress(let progress): min(1, max(0, progress.percentage / 100))
        case .history(let history): min(1, max(0, history.percentage / 100))
        }
    }

    var actionTitle: String {
        switch self {
        case .reading(let entry): entry.novelProgress.isFinished ? "Read again" : "Continue"
        case .progress, .history: "Resume"
        }
    }

    var actionSystemImage: String {
        switch self {
        case .reading(let entry): entry.novelProgress.isFinished ? "arrow.counterclockwise" : "book.fill"
        case .progress, .history: "play.fill"
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
            || detail.localizedCaseInsensitiveContains(query)
            || kind.localizedCaseInsensitiveContains(query)
    }
}

/// Builds the muted detail line for an activity row.
enum ActivityDetail {
    /// "Ch. 1929 of 3171 · 61%", "Ch. 3171 of 3171 · Finished", or
    /// "Reading" until the current chapter is known.
    static func reading(_ progress: NovelProgress) -> String {
        guard let label = progress.label else { return "Reading" }
        if progress.isFinished { return label + " · Finished" }
        guard let percent = progress.displayPercentage else { return label }
        return label + " · " + String(percent) + "%"
    }

    static func playback(
        title: String,
        unitTitle: String?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        mediaType: MediaAccountType,
        positionSeconds: Double,
        durationSeconds: Double,
        completed: Bool
    ) -> String {
        let trimmedUnit = unitTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = (trimmedUnit?.isEmpty == false && trimmedUnit != title) ? trimmedUnit : nil

        let position: String? = if let seasonNumber, let episodeNumber {
            "S\(seasonNumber) E\(episodeNumber)"
        } else if let episodeNumber {
            "Episode \(episodeNumber)"
        } else {
            nil
        }

        let label: String
        if let position, let unit,
           !unit.lowercased().hasPrefix("episode "),
           !unit.localizedCaseInsensitiveContains(position) {
            label = "\(position) · \(unit)"
        } else {
            label = position ?? unit ?? kindLabel(mediaType)
        }

        return [label, remaining(position: positionSeconds, duration: durationSeconds, completed: completed)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    static func remaining(position: Double, duration: Double, completed: Bool) -> String? {
        if completed { return "Finished" }
        guard duration > 0 else { return nil }
        let minutes = Int((max(0, duration - position) / 60).rounded(.up))
        guard minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) min left" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h left" : "\(hours) h \(rest) min left"
    }

    private static func kindLabel(_ mediaType: MediaAccountType) -> String {
        switch mediaType {
        case .anime: "Anime"
        case .movie: "Film"
        case .football: "Match"
        }
    }
}

// MARK: - Row

/// A timeline row: 2:3 thumbnail, title, muted detail, light-line progress,
/// and an always-visible resume action. Shared with the account page.
struct ActivityTimelineRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let imageURL: URL?
    var fallbackSystemImage = "photo"
    let title: String
    let detail: String
    var timestamp: String?
    var fraction: Double?
    var actionTitle = "Resume"
    var actionSystemImage = "play.fill"
    var isPrimaryAction = false
    var canAct = true
    var select: (() -> Void)?
    var selectHelp: String?
    var actionAccessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if let select {
                Button(action: select) {
                    summary
                }
                .buttonStyle(.plain)
                .help(selectHelp ?? "Show details for \(title)")
                .accessibilityLabel(title)
                .accessibilityValue(detail)
            } else {
                summary
                    .accessibilityElement(children: .combine)
            }

            if let timestamp {
                Text(timestamp)
                    .font(.asterionMono(11))
                    .foregroundStyle(Color.asterionFaint)
                    .lineLimit(1)
                    .fixedSize()
            }

            if canAct {
                actionButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(isHovering ? 0.04 : 0))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
    }

    private var summary: some View {
        HStack(spacing: 16) {
            ActivityThumbnail(url: imageURL, fallbackSystemImage: fallbackSystemImage)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.asterionDisplay(14.5, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.asterionMuted)
                    .lineLimit(1)
                if let fraction {
                    AsterionLightLine(fraction: fraction, height: 3)
                        .frame(maxWidth: 260)
                        .padding(.top, 8)
                }
            }

            Spacer(minLength: 12)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var actionButton: some View {
        let button = Button(action: action) {
            Label(actionTitle, systemImage: actionSystemImage)
        }
        .help("\(actionTitle) \(title)")
        .accessibilityLabel(actionAccessibilityLabel ?? actionTitle)

        if isPrimaryAction {
            button.buttonStyle(.asterionPrimary)
        } else {
            button.buttonStyle(.asterionSecondary)
        }
    }
}

/// 2:3 artwork thumbnail used in timeline rows.
struct ActivityThumbnail: View {
    let url: URL?
    var fallbackSystemImage = "photo"
    var width: CGFloat = 52
    var height: CGFloat = 78

    var body: some View {
        ArtworkImage(url: url, fallbackSystemImage: fallbackSystemImage)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.asterionBorder)
            }
            .accessibilityHidden(true)
    }
}

/// 1pt hairline between rows inside a panel, inset past the thumbnail.
struct ActivityRowSeparator: View {
    var leadingInset: CGFloat = 84

    var body: some View {
        Rectangle()
            .fill(Color.asterionHairline)
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}
