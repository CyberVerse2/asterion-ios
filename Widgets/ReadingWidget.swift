import AppIntents
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
