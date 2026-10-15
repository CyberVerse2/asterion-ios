import AppIntents
import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct ReadingEntry: TimelineEntry {
    let date: Date
    let snapshot: ContinueReadingSnapshot?
}

struct ReadingTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = ReadingEntry
    typealias Intent = ReadingWidgetIntent

    func placeholder(in context: Context) -> ReadingEntry {
        ReadingEntry(
            date: .now,
            snapshot: ContinueReadingSnapshot(
                novelId: "preview-novel",
                novelTitle: "Asterion",
                chapterId: "preview-chapter",
                chapterTitle: "The Threshold",
                chapterNumber: 12,
                progress: 0.42,
                updatedAt: .now
            )
        )
    }

    func snapshot(for configuration: ReadingWidgetIntent, in context: Context) async -> ReadingEntry {
        ReadingEntry(date: .now, snapshot: ContinueReadingStore.loadSnapshot() ?? placeholder(in: context).snapshot)
    }

    func timeline(for configuration: ReadingWidgetIntent, in context: Context) async -> Timeline<ReadingEntry> {
        let entry = ReadingEntry(date: .now, snapshot: ContinueReadingStore.loadSnapshot())
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900)))
    }
}

// MARK: - Palette

/// The widget extension cannot see the app's Theme tokens, so the monochrome
/// palette is restated here: a dark room, white light, colour only for state.
private enum WidgetPalette {
    static let canvas = Color(.sRGB, red: 0x0E / 255, green: 0x0F / 255, blue: 0x13 / 255)
    static let surface = Color(.sRGB, red: 0x16 / 255, green: 0x17 / 255, blue: 0x1C / 255)
    static let text = Color(.sRGB, red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF5 / 255)
    static let muted = Color(.sRGB, red: 0x9A / 255, green: 0x9D / 255, blue: 0xA8 / 255)
    static let faint = Color(.sRGB, red: 0x5E / 255, green: 0x61 / 255, blue: 0x6C / 255)
    static let success = Color(.sRGB, red: 0x52 / 255, green: 0xC9 / 255, blue: 0x8F / 255)
    static let warning = Color(.sRGB, red: 0xE9 / 255, green: 0xA9 / 255, blue: 0x45 / 255)
    static let live = Color(.sRGB, red: 0xFF / 255, green: 0x4F / 255, blue: 0x5A / 255)
    static let track = Color.white.opacity(0.14)
    static let hairline = Color.white.opacity(0.08)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }

    static func eyebrow(_ size: CGFloat = 9.5) -> Font {
        .system(size: size, weight: .semibold).width(.expanded)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Progress as a line of white light on a dark track.
private struct WidgetLightLine: View {
    let fraction: Double
    var height: CGFloat = 3
    var color: Color = WidgetPalette.text

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetPalette.track)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * clamped)
                    .shadow(color: color.opacity(0.6), radius: 3)
                    .opacity(clamped > 0 ? 1 : 0)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((min(1, max(0, fraction)) * 100).rounded())) percent")
    }
}

private struct WidgetEyebrow: View {
    let text: String
    var color: Color = WidgetPalette.muted

    var body: some View {
        Text(text.uppercased())
            .font(WidgetPalette.eyebrow())
            .tracking(1.2)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Circular progress: a white ring of light on a dark track, with an
/// optional glyph or label in the middle. Used in the Dynamic Island.
private struct WidgetProgressRing<Center: View>: View {
    let fraction: Double
    var lineWidth: CGFloat = 2.5
    var tint: Color = WidgetPalette.text
    @ViewBuilder var center: () -> Center

    var body: some View {
        let clamped = min(1, max(0, fraction))
        ZStack {
            Circle()
                .stroke(WidgetPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.001))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.6), radius: 2)
                .opacity(clamped > 0 ? 1 : 0)
            center()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

extension WidgetProgressRing where Center == EmptyView {
    init(fraction: Double, lineWidth: CGFloat = 2.5, tint: Color = WidgetPalette.text) {
        self.init(fraction: fraction, lineWidth: lineWidth, tint: tint) { EmptyView() }
    }
}

/// "Chapter 12: The Gate" → 12, for the compact mono label.
private func chapterNumber(in title: String) -> Int? {
    let pattern = #"(?i)\bch(?:apter)?\.?\s*(\d+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
          let range = Range(match.range(at: 1), in: title) else {
        return nil
    }
    return Int(title[range])
}

// MARK: - Home screen and Lock Screen widget

struct ReadingWidgetEntryView: View {
    let entry: ReadingEntry
    @Environment(\.widgetFamily) private var family

    private var isCompact: Bool { family == .systemSmall }

    var body: some View {
        switch family {
        case .accessoryInline:
            inlineLayout
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            Button(intent: ContinueReadingIntent()) { circularLayout }
                .buttonStyle(.plain)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            Button(intent: ContinueReadingIntent()) { rectangularLayout }
                .buttonStyle(.plain)
                .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            Button(intent: ContinueReadingIntent()) { mediumLayout }
                .buttonStyle(.plain)
                .containerBackground(for: .widget) { canvasBackground }
        default:
            Button(intent: ContinueReadingIntent()) { standardLayout }
                .buttonStyle(.plain)
                .containerBackground(for: .widget) { canvasBackground }
        }
    }

    private var canvasBackground: some View {
        ZStack {
            WidgetPalette.canvas
            RadialGradient(
                colors: [Color.white.opacity(0.07), .clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 220
            )
        }
    }

    // MARK: Small / large

    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let snapshot = entry.snapshot {
                Spacer(minLength: 8)

                Text(snapshot.novelTitle)
                    .font(WidgetPalette.title(isCompact ? 16 : 20))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text(chapterLine(for: snapshot))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(1)
                    .padding(.top, 4)

                Spacer(minLength: 10)

                progressFooter(for: snapshot)
            } else {
                Spacer(minLength: 8)
                emptyMessage
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium: cover left, reading state right

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            if let snapshot = entry.snapshot {
                ReadingCoverView(data: snapshot.coverImageData)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    header

                    Spacer(minLength: 6)

                    Text(snapshot.novelTitle)
                        .font(WidgetPalette.title(18))
                        .foregroundStyle(WidgetPalette.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text(chapterLine(for: snapshot))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WidgetPalette.muted)
                        .lineLimit(1)
                        .padding(.top, 4)

                    Spacer(minLength: 8)

                    progressFooter(for: snapshot)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ReadingCoverView(data: nil)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 8)
                    emptyMessage
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Lock Screen

    private var circularLayout: some View {
        ZStack {
            AccessoryWidgetBackground()
            WidgetProgressRing(fraction: entry.snapshot?.progress ?? 0, lineWidth: 4) {
                Image(systemName: entry.snapshot == nil ? "book.closed" : "book.pages.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WidgetPalette.text)
                    .widgetAccentable()
            }
            .padding(4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.snapshot.map { "\($0.novelTitle), \(percent(for: $0)) percent read" } ?? "Nothing in progress")
    }

    private var rectangularLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let snapshot = entry.snapshot {
                Text(snapshot.novelTitle)
                    .font(WidgetPalette.title(13))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .widgetAccentable()
                Text(chapterLine(for: snapshot))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    WidgetLightLine(fraction: snapshot.progress, height: 3)
                    Text("\(percent(for: snapshot))%")
                        .font(WidgetPalette.mono(11, weight: .semibold))
                        .foregroundStyle(WidgetPalette.text)
                        .fixedSize()
                }
                .padding(.top, 4)
            } else {
                Label("Asterion", systemImage: "book.closed")
                    .font(WidgetPalette.title(13))
                    .foregroundStyle(WidgetPalette.text)
                    .widgetAccentable()
                Text("Nothing in progress")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.muted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inlineLayout: some View {
        if let snapshot = entry.snapshot {
            Label(inlineText(for: snapshot), systemImage: "book.pages")
        } else {
            Label("Nothing in progress", systemImage: "book.closed")
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 6) {
            WidgetEyebrow(text: "Continue reading")
            Spacer(minLength: 4)
            Image(systemName: "book.pages")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetPalette.muted)
        }
    }

    private var emptyMessage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing in progress")
                .font(WidgetPalette.title(isCompact ? 15 : 18))
                .foregroundStyle(WidgetPalette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text("Open Asterion and start a chapter to pick it up here.")
                .font(.system(size: 12))
                .foregroundStyle(WidgetPalette.muted)
                .lineLimit(3)
        }
    }

    private func progressFooter(for snapshot: ContinueReadingSnapshot) -> some View {
        VStack(spacing: 7) {
            WidgetLightLine(fraction: snapshot.progress)
            HStack {
                Text("\(percent(for: snapshot))%")
                    .font(WidgetPalette.mono(11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.text)
                Spacer(minLength: 4)
                if snapshot.chapterNumber > 0 {
                    Text("Ch. \(snapshot.chapterNumber)")
                        .font(WidgetPalette.mono(11))
                        .foregroundStyle(WidgetPalette.muted)
                }
            }
        }
    }

    private func percent(for snapshot: ContinueReadingSnapshot) -> Int {
        Int((min(1, max(0, snapshot.progress)) * 100).rounded())
    }

    /// "Ch. 12 · Shadow Slave · 42%"
    private func inlineText(for snapshot: ContinueReadingSnapshot) -> String {
        var parts: [String] = []
        if snapshot.chapterNumber > 0 {
            parts.append("Ch. \(snapshot.chapterNumber)")
        }
        parts.append(snapshot.novelTitle)
        parts.append("\(percent(for: snapshot))%")
        return parts.joined(separator: " · ")
    }

    private func chapterLine(for snapshot: ContinueReadingSnapshot) -> String {
        guard snapshot.chapterNumber > 0 else { return snapshot.chapterTitle }
        let title = snapshot.chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Chapter \(snapshot.chapterNumber)" : "Ch. \(snapshot.chapterNumber) · \(title)"
    }
}

/// The stored cover thumbnail, or a quiet surface with a book glyph.
private struct ReadingCoverView: View {
    let data: Data?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            shape.fill(WidgetPalette.surface)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else {
                Image(systemName: "book.closed")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(WidgetPalette.faint)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(WidgetPalette.hairline))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}

struct ReadingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "ReadingWidget",
            intent: ReadingWidgetIntent.self,
            provider: ReadingTimelineProvider()
        ) { entry in
            ReadingWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Reading progress")
        .description("Continue where you left off.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

// MARK: - Story Live Activities (reading, downloading, watching)

/// Concept B, "one line of light": monochrome, no artwork. The island is
/// a quiet block of text, and the only thing that glows is the progress.
private struct LightBlock {
    var symbol: String
    var eyebrow: String
    var title: String
    var subtitle: String
    var fraction: Double
    /// Compact trailing label: "Ch 1929", "12/40", "48m".
    var compact: String
    /// Footer, left and right: "42%" · "~9 min left".
    var footLeading: String
    var footTrailing: String?
    var accent: Color = WidgetPalette.text
    var eyebrowColor: Color = WidgetPalette.muted
}

private func percentText(_ fraction: Double) -> String {
    "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
}

/// "Chapter 1929 - 1929: First Generation" → "First Generation".
private func chapterName(in title: String) -> String? {
    var rest = title.trimmingCharacters(in: .whitespaces)
    if let range = rest.range(of: #"^(chapter|ch\.?)\s*\d+"#, options: [.regularExpression, .caseInsensitive]) {
        rest.removeSubrange(range)
    }
    if let range = rest.range(of: #"^[\s\-–—:.·]*(\d+\s*[:.\-–—]\s*)?"#, options: .regularExpression) {
        rest.removeSubrange(range)
    }
    rest = rest.trimmingCharacters(in: .whitespaces)
    return rest.isEmpty ? nil : rest
}

/// The expanded island and the Lock Screen share this block.
private struct LightBlockView: View {
    let block: LightBlock
    var titleSize: CGFloat = 19

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(block.eyebrow.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(block.eyebrowColor)
                .lineLimit(1)
            Text(block.title)
                .font(.system(size: titleSize, weight: .medium))
                .foregroundStyle(WidgetPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 4)
            Text(block.subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(WidgetPalette.muted)
                .lineLimit(1)
                .padding(.top, 2)
            WidgetLightLine(fraction: block.fraction, height: 3, color: block.accent)
                .padding(.top, 14)
            HStack {
                Text(block.footLeading)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                if let trailing = block.footTrailing {
                    Text(trailing)
                        .contentTransition(.numericText())
                }
            }
            .font(WidgetPalette.mono(11))
            .foregroundStyle(WidgetPalette.faint)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A short label with the progress drawn as a hairline under it, so the
/// compact island still carries its one line of light.
private struct CompactLightLabel: View {
    let text: String
    let fraction: Double
    var accent: Color = WidgetPalette.text

    var body: some View {
        Text(text)
            .font(WidgetPalette.mono(12, weight: .medium))
            .foregroundStyle(WidgetPalette.text)
            .lineLimit(1)
            .contentTransition(.numericText())
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                WidgetLightLine(fraction: fraction, height: 2, color: accent)
            }
            .frame(maxWidth: 58, alignment: .trailing)
    }
}

private func lightIsland(_ block: LightBlock) -> DynamicIsland {
    DynamicIsland {
        DynamicIslandExpandedRegion(.bottom) {
            LightBlockView(block: block)
                .padding(.horizontal, 10)
                .padding(.top, 2)
                .padding(.bottom, 4)
        }
    } compactLeading: {
        Image(systemName: block.symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(WidgetPalette.text)
    } compactTrailing: {
        CompactLightLabel(text: block.compact, fraction: block.fraction, accent: block.accent)
    } minimal: {
        WidgetProgressRing(fraction: block.fraction, lineWidth: 2.5, tint: block.accent)
            .frame(width: 20, height: 20)
    }
    .keylineTint(WidgetPalette.text.opacity(0.35))
}

private struct LightLockScreen: View {
    let block: LightBlock

    var body: some View {
        LightBlockView(block: block, titleSize: 18)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
    }
}

// MARK: Reading

struct ReadingSessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingSessionActivityAttributes.self) { context in
            LightLockScreen(block: block(context))
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(WidgetPalette.text)
        } dynamicIsland: { context in
            lightIsland(block(context))
        }
    }

    private func block(_ context: ActivityViewContext<ReadingSessionActivityAttributes>) -> LightBlock {
        let state = context.state
        let total = max(state.totalLines, 1)
        let line = max(0, min(state.currentLine, total - 1))
        let fraction = total > 1 ? Double(line) / Double(total - 1) : 0
        let number = chapterNumber(in: state.chapterTitle)
        let name = chapterName(in: state.chapterTitle)
        let subtitle: String
        switch (number, name) {
        case let (number?, name?): subtitle = "Ch \(number) · \(name)"
        case let (number?, nil): subtitle = "Chapter \(number)"
        default: subtitle = state.chapterTitle
        }
        return LightBlock(
            symbol: "book.closed",
            eyebrow: "Reading now",
            title: context.attributes.novelTitle,
            subtitle: subtitle,
            fraction: fraction,
            compact: number.map { "Ch \($0)" } ?? percentText(fraction),
            footLeading: percentText(fraction),
            footTrailing: state.minutesLeft.map { "~\($0) min left" }
        )
    }
}

// MARK: Downloading

struct ChapterDownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChapterDownloadActivityAttributes.self) { context in
            LightLockScreen(block: block(context))
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(WidgetPalette.text)
        } dynamicIsland: { context in
            lightIsland(block(context))
        }
    }

    private func block(_ context: ActivityViewContext<ChapterDownloadActivityAttributes>) -> LightBlock {
        let state = context.state
        let fraction = Double(state.completed) / Double(max(state.total, 1))
        let done = state.total > 0 && state.completed >= state.total
        let status = state.statusText.lowercased()
        let failed = status.contains("fail") || status.contains("error") || status.contains("couldn")
        let accent = failed ? WidgetPalette.warning : (done ? WidgetPalette.success : WidgetPalette.text)
        return LightBlock(
            symbol: done ? "checkmark" : (failed ? "exclamationmark.triangle" : "arrow.down"),
            eyebrow: failed ? "Download stopped" : (done ? "Downloaded" : "Downloading"),
            title: context.attributes.novelTitle,
            subtitle: "\(state.completed) of \(state.total) chapters",
            fraction: fraction,
            compact: done ? "Done" : "\(state.completed)/\(state.total)",
            footLeading: percentText(fraction),
            footTrailing: done ? "Ready offline" : nil,
            accent: accent,
            eyebrowColor: failed ? WidgetPalette.warning : (done ? WidgetPalette.success : WidgetPalette.muted)
        )
    }
}

// MARK: Watching

struct WatchingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WatchingActivityAttributes.self) { context in
            LightLockScreen(block: block(context))
                .opacity(context.isStale ? 0.6 : 1)
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(WidgetPalette.text)
        } dynamicIsland: { context in
            lightIsland(block(context))
        }
    }

    private func block(_ context: ActivityViewContext<WatchingActivityAttributes>) -> LightBlock {
        let state = context.state
        let duration = max(state.durationSeconds, 0)
        let fraction = duration > 0 ? min(1, max(0, state.positionSeconds / duration)) : 0
        let remaining = max(0, duration - state.positionSeconds)
        let playing = state.isPlaying && !context.isStale
        return LightBlock(
            symbol: playing ? "play.fill" : "pause.fill",
            eyebrow: playing ? "Now playing" : "Paused",
            title: context.attributes.title,
            subtitle: state.unitLabel,
            fraction: fraction,
            compact: duration > 0 ? shortRemaining(remaining) : percentText(fraction),
            footLeading: percentText(fraction),
            footTrailing: duration > 0 ? longRemaining(remaining) : nil
        )
    }

    /// "48m" / "1h 12m" for the compact label.
    private func shortRemaining(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(max(minutes, 0))m"
    }

    private func longRemaining(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes <= 0 { return "Almost done" }
        if minutes >= 60 { return "\(minutes / 60) h \(minutes % 60) min left" }
        return "\(minutes) min left"
    }
}

// MARK: - Match Live Activity

/// Static red dot + LIVE. Widgets cannot animate the app's pulsing badge.
private struct WidgetLiveBadge: View {
    var size: CGFloat = 9.5

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(WidgetPalette.live)
                .frame(width: size * 0.63, height: size * 0.63)
                .shadow(color: WidgetPalette.live.opacity(0.9), radius: 3)
            Text("LIVE")
                .font(.system(size: size, weight: .heavy).width(.expanded))
                .tracking(1)
                .foregroundStyle(WidgetPalette.live)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live")
    }
}

/// Team initials in a smoked circle, standing in for the crest.
private struct WidgetTeamMark: View {
    let name: String
    var size: CGFloat = 36

    var body: some View {
        Text(teamInitials(name))
            .font(.system(size: size * 0.3, weight: .bold).width(.expanded))
            .foregroundStyle(WidgetPalette.text.opacity(0.88))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.08)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

/// "Arsenal" → "ARS", "Manchester United" → "MU" (matches the app's crests).
private func teamInitials(_ name: String) -> String {
    let words = name.split(separator: " ").filter { !$0.isEmpty }
    let letters = words.count > 1 ? words.prefix(2).compactMap(\.first) : Array((words.first ?? "").prefix(3))
    return String(letters).uppercased()
}

/// "Arsenal" → "ARS", "Manchester United" → "MUN": three letters for the
/// compact island.
private func teamCode(_ name: String) -> String {
    let words = name.split(separator: " ").filter { !$0.isEmpty }
    guard let first = words.first else { return "—" }
    if words.count > 1, first.count <= 3 {
        return String(first.prefix(1) + words[1].prefix(2)).uppercased()
    }
    return String(first.prefix(3)).uppercased()
}

struct MatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            // Lock Screen and banner
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    WidgetEyebrow(text: competition(context.attributes))
                    Spacer(minLength: 4)
                    if isLive(context) {
                        WidgetLiveBadge()
                    } else {
                        Text(context.attributes.kickoff, style: .time)
                            .font(WidgetPalette.mono(11, weight: .medium))
                            .foregroundStyle(WidgetPalette.muted)
                    }
                }

                HStack(alignment: .center, spacing: 10) {
                    team(context.attributes.home, alignment: .leading)
                    VStack(spacing: 3) {
                        if isLive(context) {
                            Text("In play")
                                .font(WidgetPalette.title(15))
                                .foregroundStyle(WidgetPalette.text)
                        } else {
                            Text(context.attributes.kickoff, style: .timer)
                                .font(WidgetPalette.mono(22, weight: .semibold))
                                .foregroundStyle(WidgetPalette.text)
                                .multilineTextAlignment(.center)
                                .monospacedDigit()
                            Text("to kickoff")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WidgetPalette.faint)
                        }
                    }
                    .frame(maxWidth: 120)
                    team(context.attributes.away, alignment: .trailing)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .activityBackgroundTint(WidgetPalette.canvas.opacity(0.94))
            .activitySystemActionForegroundColor(WidgetPalette.text)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WidgetTeamMark(name: context.attributes.home, size: 40)
                        .padding(.leading, 4)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WidgetTeamMark(name: context.attributes.away, size: 40)
                        .padding(.trailing, 4)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        WidgetEyebrow(text: competition(context.attributes))
                        if isLive(context) {
                            WidgetLiveBadge(size: 12)
                        } else {
                            Text(context.attributes.kickoff, style: .timer)
                                .font(WidgetPalette.mono(20, weight: .semibold))
                                .foregroundStyle(WidgetPalette.text)
                                .multilineTextAlignment(.center)
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(context.attributes.home)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(WidgetPalette.text)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if isLive(context) {
                            Text("vs")
                                .font(WidgetPalette.mono(11, weight: .medium))
                                .foregroundStyle(WidgetPalette.muted)
                        } else {
                            Text(context.attributes.kickoff, style: .time)
                                .font(WidgetPalette.mono(11, weight: .medium))
                                .foregroundStyle(WidgetPalette.muted)
                        }
                        Spacer(minLength: 6)
                        Text(context.attributes.away)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(WidgetPalette.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                }
            } compactLeading: {
                Text("\(teamCode(context.attributes.home)) · \(teamCode(context.attributes.away))")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } compactTrailing: {
                if isLive(context) {
                    WidgetLiveBadge(size: 9)
                } else {
                    Text(context.attributes.kickoff, style: .timer)
                        .font(WidgetPalette.mono(12, weight: .semibold))
                        .foregroundStyle(WidgetPalette.text)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 56)
                }
            } minimal: {
                Image(systemName: "soccerball")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isLive(context) ? WidgetPalette.live : WidgetPalette.text)
            }
            .keylineTint(isLive(context) ? WidgetPalette.live.opacity(0.7) : WidgetPalette.text.opacity(0.6))
        }
    }

    /// Live once the app says so, or once the activity goes stale at kickoff.
    private func isLive(_ context: ActivityViewContext<MatchActivityAttributes>) -> Bool {
        context.state.isLive || context.isStale || Date() >= context.attributes.kickoff
    }

    private func competition(_ attributes: MatchActivityAttributes) -> String {
        let value = attributes.competition.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Kickoff" : value
    }

    private func team(_ name: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            WidgetTeamMark(name: name, size: 38)
            Text(name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(WidgetPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}
