import AppKit
import ClerkKit
import Observation
import SwiftUI

@MainActor
final class AsterionAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            self.presentMainWindow(in: NSApp)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else { return true }

        DispatchQueue.main.async {
            self.presentMainWindow(in: sender)
        }
        return true
    }

    private func presentMainWindow(in application: NSApplication) {
        application.activate(ignoringOtherApps: true)

        if let window = application.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let newWindowItem = application.mainMenu?
            .items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first(where: {
                $0.keyEquivalent.lowercased() == "n"
                    && $0.keyEquivalentModifierMask.contains(.command)
            }), let action = newWindowItem.action else {
            preconditionFailure("Asterion's native New Window command is unavailable")
        }

        application.sendAction(action, to: newWindowItem.target, from: newWindowItem)
    }
}

@main
@MainActor
struct AsterionApp: App {
    private static let clerkPublishableKeyInfoKey = "AsterionClerkPublishableKey"

    private static var clerkPublishableKey: String {
        #if DEBUG
        "pk_test_cG9ldGljLWdhdG9yLTk3LmNsZXJrLmFjY291bnRzLmRldiQ"
        #else
        guard let key = Bundle.main.object(forInfoDictionaryKey: clerkPublishableKeyInfoKey) as? String,
              key.hasPrefix("pk_") else {
            fatalError(
                "Release builds require a Clerk publishable key in the "
                    + "\(clerkPublishableKeyInfoKey) Info.plist entry."
            )
        }
        return key
        #endif
    }

    @NSApplicationDelegateAdaptor(AsterionAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = AppModel()
    @StateObject private var mediaDownloads = MediaDownloadManager()

    init() {
        ClerkKeychainMigration.migrateLegacySessionIfNeeded()
        let options = Clerk.Options(
            keychainConfig: .init(service: ClerkKeychainMigration.currentService)
        )
        Clerk.configure(
            publishableKey: Self.clerkPublishableKey,
            options: options
        )
    }

    var body: some Scene {
        WindowGroup("Asterion", id: "main") {
            ContentView()
                .containerBackground(Color.asterionMediaCanvas, for: .window)
                .preferredColorScheme(.dark)
                .environmentObject(model)
                .environmentObject(mediaDownloads)
                .environment(Clerk.shared)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.reconcileAuthenticationState() }
                }
                .asterionHandoffReceiver()
        }
        // Handoff (and any other external event) is routed to the main window,
        // which opens the reader or player window it targets.
        .handlesExternalEvents(matching: ["*"])
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1420, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            AsterionNavigationCommands()
        }

        WindowGroup("Reader", for: ReaderRoute.self) { $route in
            if let route {
                ReaderView(route: route)
                    .environmentObject(model)
            }
        }
        .defaultSize(width: 840, height: 900)
        .handlesExternalEvents(matching: [])

        WindowGroup("Anime Player", for: AnimePlayerRoute.self) { $route in
            if let route {
                AnimePlayerView(route: route)
                    .preferredColorScheme(.dark)
                    .environmentObject(model)
                    .environmentObject(mediaDownloads)
            }
        }
        .defaultSize(width: 1_080, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])
        .asterionMediaWindowPlacement()

        WindowGroup("Asterion Player", for: MoviePlayerRoute.self) { $route in
            if let route {
                MoviePlayerView(route: route)
                    .preferredColorScheme(.dark)
                    .environmentObject(model)
                    .environmentObject(mediaDownloads)
            }
        }
        .defaultSize(width: 1_080, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])
        .asterionMediaWindowPlacement()

        WindowGroup("Asterion Live", for: FootballPlayerRoute.self) { $route in
            if let route {
                FootballPlayerView(route: route)
                    .preferredColorScheme(.dark)
            }
        }
        .defaultSize(width: 1_080, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .handlesExternalEvents(matching: [])
        .asterionMediaWindowPlacement()

        Window("Sign In to Asterion", id: "authentication") {
            AsterionAuthenticationView()
                .containerBackground(Color.asterionMediaCanvas, for: .window)
                .preferredColorScheme(.dark)
                .environmentObject(model)
                .environment(Clerk.shared)
        }
        .defaultSize(width: 438, height: 548)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
        }
    }
}

private extension Scene {
    func asterionMediaWindowPlacement() -> some Scene {
        defaultWindowPlacement { content, context in
            AsterionMediaWindowPlacement.defaultPlacement(
                contentSize: content.sizeThatFits(.unspecified),
                visibleSize: context.defaultDisplay.visibleRect.size
            )
        }
        .windowIdealPlacement { _, context in
            AsterionMediaWindowPlacement.idealPlacement(
                visibleSize: context.defaultDisplay.visibleRect.size
            )
        }
    }
}

private enum AsterionMediaWindowPlacement {
    private static let preferredSize = CGSize(width: 1_080, height: 700)
    private static let aspectRatio = preferredSize.width / preferredSize.height

    static func defaultPlacement(contentSize: CGSize, visibleSize: CGSize) -> WindowPlacement {
        let measuredWidth = contentSize.width.isFinite && contentSize.width > 0
            ? contentSize.width
            : preferredSize.width
        let requestedWidth = max(preferredSize.width, measuredWidth)
        let size = fittedSize(
            requestedWidth: requestedWidth,
            visibleSize: visibleSize,
            widthFraction: 0.90,
            heightFraction: 0.86
        )
        return WindowPlacement(.center, size: size)
    }

    static func idealPlacement(visibleSize: CGSize) -> WindowPlacement {
        let size = fittedSize(
            requestedWidth: .greatestFiniteMagnitude,
            visibleSize: visibleSize,
            widthFraction: 0.94,
            heightFraction: 0.90
        )
        return WindowPlacement(.center, size: size)
    }

    private static func fittedSize(
        requestedWidth: CGFloat,
        visibleSize: CGSize,
        widthFraction: CGFloat,
        heightFraction: CGFloat
    ) -> CGSize {
        let maximumWidth = max(1, visibleSize.width * widthFraction)
        let maximumHeight = max(1, visibleSize.height * heightFraction)
        let width = min(requestedWidth, maximumWidth, maximumHeight * aspectRatio)
        return CGSize(width: width, height: width / aspectRatio)
    }
}

struct AsterionNavigationCommands: Commands {
    @FocusedBinding(\.asterionDestination) private var destination
    @FocusedBinding(\.asterionSection) private var section
    @FocusedBinding(\.asterionAnimeSection) private var animeSection
    @FocusedBinding(\.asterionMovieSection) private var movieSection
    @FocusedBinding(\.asterionFootballSection) private var footballSection

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Home") { destination = .home }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(destination == nil)
            Button("Novels") { destination = .novels }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(destination == nil)
            Button("Anime") { destination = .anime }
                .keyboardShortcut("3", modifiers: [.command, .option])
                .disabled(destination == nil)
            Button("Movies") { destination = .movies }
                .keyboardShortcut("4", modifiers: [.command, .option])
                .disabled(destination == nil)
            Button("Football") { destination = .football }
                .keyboardShortcut("5", modifiers: [.command, .option])
                .disabled(destination == nil)
            Button("Continue") { destination = .continueActivity }
                .keyboardShortcut("6", modifiers: [.command, .option])
                .disabled(destination == nil)
            Button("Bookmarks") { destination = .bookmarks }
                .keyboardShortcut("7", modifiers: [.command, .option])
                .disabled(destination == nil)
            Button("Downloads") { destination = .downloads }
                .keyboardShortcut("8", modifiers: [.command, .option])
                .disabled(destination == nil)
            Button("History") { destination = .history }
                .keyboardShortcut("9", modifiers: [.command, .option])
                .disabled(destination == nil)

            Divider()

            if destination == .anime {
                ForEach(Array(AnimeSection.allCases.enumerated()), id: \.element) { index, item in
                    if index < 9 {
                        Button(item.title) { animeSection = item }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                            .disabled(animeSection == nil)
                    } else {
                        Button(item.title) { animeSection = item }
                            .disabled(animeSection == nil)
                    }
                }
            } else if destination == .movies {
                ForEach(Array(MovieSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { movieSection = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(movieSection == nil)
                }
            } else if destination == .football {
                ForEach(Array(FootballSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { footballSection = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(footballSection == nil)
                }
            } else if destination == .novels {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { section = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(section == nil)
                }
            }

            Divider()

            Button("Account") { destination = .account }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(destination == nil)
        }
    }
}

extension FocusedValues {
    @Entry var asterionDestination: Binding<AppDestination>?
    @Entry var asterionSection: Binding<AppSection>?
    @Entry var asterionAnimeSection: Binding<AnimeSection>?
    @Entry var asterionMovieSection: Binding<MovieSection>?
    @Entry var asterionFootballSection: Binding<FootballSection>?
}

// MARK: - Handoff

/// Handoff contract shared with the iOS app. Both sides must agree on the
/// activity types and userInfo keys exactly.
enum AsterionHandoff {
    static let readingActivityType = "cloud.cyberverse.asterion.reading"
    static let watchingActivityType = "cloud.cyberverse.asterion.watching"

    /// Advertised state is refreshed at most this often while it changes.
    static let updateInterval: Duration = .seconds(5)
    /// A received request that no window has consumed is ignored after this.
    static let requestLifetime: TimeInterval = 90

    enum WatchingMediaType: String, Sendable {
        case anime
        case movie
    }

    struct ReadingRequest: Equatable, Sendable {
        let id = UUID()
        let route: ReaderRoute
        /// Paragraph index into the sender's paragraph list.
        let line: Int?
        /// Optional (newer senders): the sender's paragraph count and its
        /// position as a 0...1 fraction, used when our count differs.
        let lineCount: Int?
        let progress: Double?
        let novelTitle: String
        let receivedAt = Date()

        init?(activity: NSUserActivity) {
            guard activity.activityType == AsterionHandoff.readingActivityType,
                  let info = activity.userInfo,
                  let novelID = AsterionHandoff.string(info["novelId"]),
                  let chapterID = AsterionHandoff.string(info["chapterId"]) else { return nil }
            route = ReaderRoute(novelID: novelID, chapterID: chapterID)
            line = AsterionHandoff.integer(info["line"]).map { max(0, $0) }
            lineCount = AsterionHandoff.integer(info["lineCount"]).flatMap { $0 > 0 ? $0 : nil }
            progress = AsterionHandoff.double(info["progress"])
                .flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
            novelTitle = AsterionHandoff.string(info["novelTitle"]) ?? ""
        }

        /// The line to open at in a chapter with `paragraphCount` paragraphs.
        func resolvedLine(paragraphCount: Int) -> Int? {
            AsterionHandoff.resolveLine(
                line: line,
                lineCount: lineCount,
                progress: progress,
                paragraphCount: paragraphCount
            )
        }
    }

    /// Prefers the paragraph index when both sides split the chapter into the
    /// same number of paragraphs (or the sender didn't say); otherwise maps
    /// the sender's fraction onto our paragraphs.
    static func resolveLine(line: Int?, lineCount: Int?, progress: Double?, paragraphCount: Int) -> Int? {
        let lastLine = max(0, paragraphCount - 1)
        if let progress, paragraphCount > 0,
           line == nil || (lineCount != nil && lineCount != paragraphCount) {
            return min(lastLine, max(0, Int((progress * Double(lastLine)).rounded())))
        }
        return line.map { min($0, lastLine) }
    }

    /// Position as sent in "progress": 0 at the first paragraph, 1 at the last.
    static func readingProgress(line: Int, paragraphCount: Int) -> Double {
        guard paragraphCount > 1 else { return 0 }
        return min(1, max(0, Double(line) / Double(paragraphCount - 1)))
    }

    /// The contract's anime unit is "<animeID>-<episodeNumber>" (what iOS
    /// sends); macOS episode ids are "<animeID>:<episodeNumber>".
    static func handoffAnimeUnitID(fromEpisodeID episodeID: String) -> String {
        guard let separator = episodeID.lastIndex(of: ":"),
              !episodeID[episodeID.index(after: separator)...].isEmpty,
              episodeID[episodeID.index(after: separator)...].allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return episodeID
        }
        return episodeID.replacingCharacters(in: separator...separator, with: "-")
    }

    /// Accepts either form and returns the macOS episode id.
    static func animeEpisodeID(fromHandoffUnitID unitID: String) -> String {
        guard !unitID.contains(":"),
              let separator = unitID.lastIndex(of: "-"),
              separator != unitID.startIndex,
              !unitID[unitID.index(after: separator)...].isEmpty,
              unitID[unitID.index(after: separator)...].allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return unitID
        }
        return unitID.replacingCharacters(in: separator...separator, with: ":")
    }

    struct WatchingRequest: Equatable, Sendable {
        let id = UUID()
        let mediaType: WatchingMediaType
        let contentID: String
        /// macOS episode id (anime "<animeID>:<n>", TV episode slug); empty
        /// for a film.
        let unitID: String
        let positionSeconds: Double?
        let title: String
        let receivedAt = Date()

        init?(activity: NSUserActivity) {
            guard activity.activityType == AsterionHandoff.watchingActivityType,
                  let info = activity.userInfo,
                  let rawType = AsterionHandoff.string(info["mediaType"]),
                  let mediaType = WatchingMediaType(rawValue: rawType),
                  let contentID = AsterionHandoff.string(info["contentId"]) else { return nil }
            self.mediaType = mediaType
            self.contentID = contentID
            let sentUnitID = AsterionHandoff.string(info["unitId"]) ?? ""
            unitID = mediaType == .anime
                ? AsterionHandoff.animeEpisodeID(fromHandoffUnitID: sentUnitID)
                : sentUnitID
            positionSeconds = AsterionHandoff.double(info["positionSeconds"])
                .flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let sentTitle = AsterionHandoff.string(info["title"]) ?? activity.title ?? ""
            title = sentTitle.isEmpty ? "Asterion" : sentTitle
        }

        var episodeID: String? { unitID.isEmpty ? nil : unitID }

        /// The player window this request is shown in. The receiver points it
        /// at an already open window for the same title when there is one.
        var animeRoute: AnimePlayerRoute {
            openAnimeRoute ?? AnimePlayerRoute(slug: contentID, title: title, initialEpisodeID: episodeID)
        }

        var movieRoute: MoviePlayerRoute {
            openMovieRoute ?? MoviePlayerRoute(slug: contentID, title: title, initialEpisodeID: episodeID)
        }

        var openAnimeRoute: AnimePlayerRoute?
        var openMovieRoute: MoviePlayerRoute?
    }

    @MainActor
    static func configureReading(
        _ activity: NSUserActivity,
        novelID: String,
        chapterID: String,
        line: Int,
        lineCount: Int,
        novelTitle: String,
        chapterTitle: String
    ) {
        let line = max(0, line)
        activity.title = novelTitle.isEmpty ? chapterTitle : novelTitle
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.userInfo = [
            "novelId": novelID,
            "chapterId": chapterID,
            "line": line,
            "lineCount": max(0, lineCount),
            "progress": readingProgress(line: line, paragraphCount: lineCount),
            "novelTitle": novelTitle,
            "chapterTitle": chapterTitle,
        ]
        activity.needsSave = true
    }

    @MainActor
    static func configureWatching(
        _ activity: NSUserActivity,
        mediaType: WatchingMediaType,
        contentID: String,
        unitID: String,
        positionSeconds: Double,
        title: String,
        imageURL: URL?
    ) {
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        var info: [String: Any] = [
            "mediaType": mediaType.rawValue,
            "contentId": contentID,
            "unitId": mediaType == .anime ? handoffAnimeUnitID(fromEpisodeID: unitID) : unitID,
            "positionSeconds": positionSeconds.isFinite ? max(0, positionSeconds) : 0,
            "title": title,
        ]
        if let imageURL {
            info["imageURL"] = imageURL.absoluteString
        }
        activity.userInfo = info
        activity.needsSave = true
    }

    private static func string(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

/// Holds the most recent Handoff request until the reader or player window it
/// targets consumes it. Requests are matched by content so the position never
/// leaks into an unrelated window, and they expire if nothing claims them.
@MainActor
@Observable
final class AsterionHandoffInbox {
    static let shared = AsterionHandoffInbox()

    private(set) var readingRequest: AsterionHandoff.ReadingRequest?
    private(set) var watchingRequest: AsterionHandoff.WatchingRequest?

    /// Routes of the player windows currently on screen, oldest first.
    @ObservationIgnored private var openAnimeRoutes: [AnimePlayerRoute] = []
    @ObservationIgnored private var openMovieRoutes: [MoviePlayerRoute] = []

    private init() {}

    func playerAppeared(_ route: AnimePlayerRoute) { openAnimeRoutes.append(route) }
    func playerAppeared(_ route: MoviePlayerRoute) { openMovieRoutes.append(route) }

    func playerDisappeared(_ route: AnimePlayerRoute) {
        if let index = openAnimeRoutes.lastIndex(of: route) { openAnimeRoutes.remove(at: index) }
    }

    func playerDisappeared(_ route: MoviePlayerRoute) {
        if let index = openMovieRoutes.lastIndex(of: route) { openMovieRoutes.remove(at: index) }
    }

    /// Points the request at an open window already playing this title, so
    /// Handoff switches that window instead of opening a second player.
    func targetingOpenWindow(_ request: AsterionHandoff.WatchingRequest) -> AsterionHandoff.WatchingRequest {
        var request = request
        switch request.mediaType {
        case .anime:
            request.openAnimeRoute = openAnimeRoutes.last { $0.slug == request.contentID }
        case .movie:
            request.openMovieRoute = openMovieRoutes.last { $0.slug == request.contentID }
        }
        return request
    }

    func deliver(_ request: AsterionHandoff.ReadingRequest) {
        readingRequest = request
    }

    func deliver(_ request: AsterionHandoff.WatchingRequest) {
        watchingRequest = request
    }

    /// Returns the handed-off line for this route once, then forgets it.
    /// `paragraphCount` is this reader's paragraph count for the chapter.
    func takeReaderLine(for route: ReaderRoute, paragraphCount: Int) -> Int? {
        guard let request = readingRequest,
              request.route == route,
              Self.isFresh(request.receivedAt) else { return nil }
        readingRequest = nil
        return request.resolvedLine(paragraphCount: paragraphCount)
    }

    /// Returns the handed-off start position for this playback unit once.
    /// `unitID` is the episode id, or "" for a film.
    func takePlaybackPosition(
        mediaType: AsterionHandoff.WatchingMediaType,
        contentID: String,
        unitID: String
    ) -> Double? {
        guard let request = watchingRequest,
              request.mediaType == mediaType,
              request.contentID == contentID,
              request.unitID == unitID,
              Self.isFresh(request.receivedAt) else { return nil }
        watchingRequest = nil
        return request.positionSeconds
    }

    private static func isFresh(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) < AsterionHandoff.requestLifetime
    }
}

/// Leading-and-trailing throttle for advertised Handoff state: the first
/// change applies immediately, later ones at most once per interval, and the
/// last submitted value always lands.
@MainActor
final class AsterionHandoffThrottle {
    private let interval: Duration
    private var lastFire: ContinuousClock.Instant?
    private var pending: Task<Void, Never>?
    private var action: (@MainActor () -> Void)?

    init(interval: Duration = AsterionHandoff.updateInterval) {
        self.interval = interval
    }

    func submit(_ action: @escaping @MainActor () -> Void) {
        self.action = action
        guard pending == nil else { return }
        let elapsed = lastFire.map { ContinuousClock.now - $0 } ?? interval
        guard elapsed < interval else {
            fire()
            return
        }
        let wait = interval - elapsed
        pending = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        action = nil
    }

    private func fire() {
        pending = nil
        lastFire = .now
        let action = self.action
        self.action = nil
        action?()
    }
}

/// Receives Handoff from the iOS app (or another Mac) in the main window and
/// opens the matching reader or player window.
private struct AsterionHandoffReceiver: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onContinueUserActivity(AsterionHandoff.readingActivityType) { activity in
                guard let request = AsterionHandoff.ReadingRequest(activity: activity) else { return }
                AsterionHandoffInbox.shared.deliver(request)
                openWindow(value: request.route)
            }
            .onContinueUserActivity(AsterionHandoff.watchingActivityType) { activity in
                guard let received = AsterionHandoff.WatchingRequest(activity: activity) else { return }
                let request = AsterionHandoffInbox.shared.targetingOpenWindow(received)
                AsterionHandoffInbox.shared.deliver(request)
                switch request.mediaType {
                case .anime:
                    openWindow(value: request.animeRoute)
                case .movie:
                    openWindow(value: request.movieRoute)
                }
            }
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }
}

extension View {
    func asterionHandoffReceiver() -> some View {
        modifier(AsterionHandoffReceiver())
    }
}
