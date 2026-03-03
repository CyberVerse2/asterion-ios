import AppIntents
import ActivityKit
import SwiftUI
import WidgetKit

struct ReadingEntry: TimelineEntry {
    let date: Date
    let novelTitle: String
    let progress: Double
}

struct ReadingTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = ReadingEntry
    typealias Intent = ReadingWidgetIntent

    func placeholder(in context: Context) -> ReadingEntry {
        ReadingEntry(date: .now, novelTitle: "Asterion", progress: 0.42)
    }

    func snapshot(for configuration: ReadingWidgetIntent, in context: Context) async -> ReadingEntry {
        ReadingEntry(date: .now, novelTitle: "Current Novel", progress: 0.57)
    }

    func timeline(for configuration: ReadingWidgetIntent, in context: Context) async -> Timeline<ReadingEntry> {
        let entry = ReadingEntry(date: .now, novelTitle: "Current Novel", progress: 0.57)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900)))
    }
}

struct ReadingWidgetEntryView: View {
    let entry: ReadingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Reading")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.novelTitle)
                .font(.headline)
                .lineLimit(2)
            ProgressView(value: entry.progress)
            Text("\(Int(entry.progress * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
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
        .configurationDisplayName("Reading Progress")
        .description("Continue where you left off.")
    }
}

struct ChapterDownloadLiveActivityWidget: Widget {
    private let gold = Color(red: 0.91, green: 0.78, blue: 0.39)
    private let card = Color(red: 0.12, green: 0.1, blue: 0.09)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChapterDownloadActivityAttributes.self) { context in
            // Lock Screen / banner UI
            VStack(alignment: .leading, spacing: 10) {
                Text("DOWNLOADING CHAPTERS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(1)
                    .foregroundStyle(gold.opacity(0.9))
                Text(context.attributes.novelTitle)
                    .font(.headline)
                    .lineLimit(1)
                ProgressView(
                    value: Double(context.state.completed),
                    total: Double(max(context.state.total, 1))
                )
                .tint(gold)
                HStack {
                    Text("\(context.state.completed)/\(context.state.total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.9))
                    Spacer()
                    Text(context.state.statusText)
                        .font(.caption2)
                        .foregroundStyle(gold.opacity(0.9))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(card.opacity(0.92))
            )
            .activityBackgroundTint(card.opacity(0.95))
            .activitySystemActionForegroundColor(gold)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.down.doc")
                        .foregroundStyle(gold)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.novelTitle)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completed)/\(context.state.total)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(gold)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(
                            value: Double(context.state.completed),
                            total: Double(max(context.state.total, 1))
                        )
                        .tint(gold)
                        HStack {
                            Text(context.state.statusText.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(0.8)
                                .foregroundStyle(gold.opacity(0.95))
                            Spacer()
                            Text("\(Int((Double(context.state.completed) / Double(max(context.state.total, 1))) * 100))%")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.down.doc")
                    .foregroundStyle(gold)
            } compactTrailing: {
                Text("\(Int((Double(context.state.completed) / Double(max(context.state.total, 1))) * 100))%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(gold)
            } minimal: {
                Image(systemName: "arrow.down.doc")
                    .foregroundStyle(gold)
            }
            .keylineTint(gold)
        }
    }
}
