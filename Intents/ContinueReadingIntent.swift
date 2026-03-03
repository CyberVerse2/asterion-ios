import AppIntents

struct ContinueReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Reading"
    static var description = IntentDescription("Open Asterion and continue your latest chapter.")

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct ReadingWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Reading Widget"
    static var description = IntentDescription("Configure your reading progress widget.")
}
