import AppIntents

struct AsterionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: ["Continue reading in \(.applicationName)"],
            shortTitle: "Continue Reading",
            systemImageName: "book.fill"
        )
    }
}
