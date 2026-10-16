import Combine
import ClerkKit
import ClerkKitUI
import Network
import SwiftUI
import UIKit
import UserNotifications

final class AsterionAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        ContentNotificationService.shared.registerBackgroundRefresh()
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let rawKind = info["asterionContentKind"] as? String,
              let kind = ContentWatchTarget.Kind(rawValue: rawKind),
              let id = info["asterionContentID"] as? String,
              let title = info["asterionContentTitle"] as? String else { return }
        let target = ContentWatchTarget(kind: kind, contentID: id, title: title)
        await MainActor.run { ContentNotificationService.shared.openTarget = target }
    }
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        PlaybackOrientationLock.mask
    }
}

enum AsterionTab: String, CaseIterable {
    case home
    case browse
    case library
    case downloads
    case account

    var label: String {
        switch self {
        case .home:      return "Home"
        case .browse:    return "Browse"
        case .library:   return "Library"
        case .downloads: return "Downloads"
        case .account:   return "Account"
        }
    }

    var systemImage: String {
        switch self {
        case .home:      return "house"
        case .browse:    return "square.grid.2x2"
        case .library:   return "books.vertical"
        case .downloads: return "arrow.down.circle"
        case .account:   return "person.crop.circle"
        }
    }
}

@MainActor
final class TabBarState: ObservableObject {
    @Published var isVisible = true
    @Published var selectedTab: AsterionTab = .home
}

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Asterion.NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

private let _clerkConfigured: Bool = {
    guard let publishableKey = Bundle.main.object(forInfoDictionaryKey: "AsterionClerkPublishableKey") as? String,
          publishableKey.hasPrefix("pk_") else {
        fatalError("AsterionClerkPublishableKey must be supplied by the app build configuration.")
    }
    Clerk.configure(publishableKey: publishableKey)
    return true
}()

@main
struct AsterionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AsterionAppDelegate.self) private var appDelegate
    @StateObject private var authService = AuthService()
    @StateObject private var apiClient = APIClient()
    @StateObject private var tabBarState = TabBarState()
    @StateObject private var readingProgressService = ReadingProgressService()
    @StateObject private var mediaAccountService = MediaAccountService()
    @StateObject private var offlineVideoDownloadService = OfflineVideoDownloadService()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var readingActivityService = ReadingActivityService()
    @StateObject private var contentNotifications = ContentNotificationService.shared
    @State private var accountReady = false

    init() {
        _ = _clerkConfigured
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(authService)
                .environmentObject(apiClient)
                .environmentObject(tabBarState)
                .environmentObject(readingProgressService)
                .environmentObject(mediaAccountService)
                .environmentObject(offlineVideoDownloadService)
                .environmentObject(networkMonitor)
                .environmentObject(readingActivityService)
                .environmentObject(contentNotifications)
                .environment(Clerk.shared)
                .tint(Color.goldAccent)
                .task {
                    authService.startClerkSessionObserver(using: apiClient)
                    await authService.syncClerkSession()
                    apiClient.setSessionToken(authService.sessionToken)
                    await authService.syncUserProfileToBackend(using: apiClient)
                    readingProgressService.configure(apiClient: apiClient)
                    readingActivityService.setUser(authService.currentUser?.id)
                    mediaAccountService.configure(apiClient: apiClient)
                    await mediaAccountService.handleAuthenticationChange(isSignedIn: authService.isSignedIn)
                    await readingProgressService.flushQueue()
                    accountReady = true
                    await refreshContentAlerts()
                }
                .onChange(of: authService.isSignedIn) { _, isSignedIn in
                    guard accountReady else { return }
                    Task {
                        apiClient.setSessionToken(authService.sessionToken)
                        readingActivityService.setUser(authService.currentUser?.id)
                        await mediaAccountService.handleAuthenticationChange(isSignedIn: isSignedIn)
                        await refreshContentAlerts()
                    }
                }
                .onChange(of: networkMonitor.isConnected) { _, isConnected in
                    guard isConnected else { return }
                    Task {
                        apiClient.setSessionToken(authService.sessionToken)
                        await readingProgressService.flushQueue()
                        await mediaAccountService.handleAuthenticationChange(isSignedIn: authService.isSignedIn)
                    }
                }
                .onChange(of: mediaAccountService.snapshot.bookmarks.map(\.id)) { _, _ in
                    guard accountReady else { return }
                    Task { await refreshContentAlerts() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .asterionSavedNovelsChanged)) { _ in
                    guard accountReady else { return }
                    Task { await refreshContentAlerts() }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard accountReady else { return }
                    if phase == .background { contentNotifications.scheduleRefresh() }
                    if phase == .active { Task { await refreshContentAlerts() } }
                }
        }
    }

    private func refreshContentAlerts() async {
        contentNotifications.setUser(authService.currentUser?.id)
        let library = authService.isSignedIn ? try? await apiClient.fetchMyLibrary() : []
        if let library {
            let catalog = await OfflineChapterStore.shared.loadCatalog()
            var targets: [ContentWatchTarget] = []
            for entry in library {
                var novel = catalog.first { $0.id == entry.novelId }
                if novel == nil { novel = try? await apiClient.fetchNovel(id: entry.novelId) }
                guard let novel else { continue }
                targets.append(ContentWatchTarget(kind: .novel, contentID: novel.id, title: novel.title))
            }
            contentNotifications.replaceTargets(kind: .novel, with: targets)
        }
        contentNotifications.replaceTargets(kind: .anime, with:
            mediaAccountService.snapshot.bookmarks.filter { $0.mediaType == .anime }.map {
                ContentWatchTarget(kind: .anime, contentID: $0.contentId, title: $0.title)
            })
        await contentNotifications.requestPermissionIfNeeded()
        await contentNotifications.checkForUpdates()
        contentNotifications.scheduleRefresh()
    }
}

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var tabBarState: TabBarState
    @EnvironmentObject private var contentNotifications: ContentNotificationService
    @AppStorage("asterion.onboarding.completed") private var hasCompletedOnboarding = false
    @State private var handoffDestination: HandoffDestination?

    var body: some View {
        Group {
            appTabView
        }
        .onAppear {
            WindowAppearance.apply(.dark)
            handlePendingContinueReadingRequest()
            MatchLiveActivityManager.shared.endExpired()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handlePendingContinueReadingRequest()
            MatchLiveActivityManager.shared.endExpired()
        }
        .fullScreenCover(isPresented: onboardingPresentation) {
            InterestOnboardingView {
                hasCompletedOnboarding = true
            }
        }
        .fullScreenCover(item: $contentNotifications.openTarget) { target in
            NavigationStack { ContentAlertDestination(target: target) }
        }
        .fullScreenCover(item: $handoffDestination) { destination in
            NavigationStack { HandoffDestinationView(destination: destination) }
        }
        .onContinueUserActivity(HandoffActivityType.reading) { activity in
            presentHandoff(HandoffDestination(readingActivity: activity))
        }
        .onContinueUserActivity(HandoffActivityType.watching) { activity in
            presentHandoff(HandoffDestination(watchingActivity: activity))
        }
    }

    /// Opens what the other device was reading or watching, replacing any
    /// cover that is already up (only one full-screen cover can show at a time).
    private func presentHandoff(_ destination: HandoffDestination?) {
        guard let destination, hasCompletedOnboarding else { return }
        guard handoffDestination != nil || contentNotifications.openTarget != nil else {
            handoffDestination = destination
            return
        }
        handoffDestination = nil
        contentNotifications.openTarget = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            handoffDestination = destination
        }
    }

    private var onboardingPresentation: Binding<Bool> {
        Binding(
            get: { !hasCompletedOnboarding },
            set: { isPresented in
                if !isPresented { hasCompletedOnboarding = true }
            }
        )
    }

    private var appTabView: some View {
        TabView(selection: $tabBarState.selectedTab) {
            Tab(AsterionTab.home.label, systemImage: AsterionTab.home.systemImage, value: .home) {
                HomeView()
            }

            Tab(AsterionTab.browse.label, systemImage: AsterionTab.browse.systemImage, value: .browse) {
                BrowseHubView()
            }

            Tab(AsterionTab.library.label, systemImage: AsterionTab.library.systemImage, value: .library) {
                LibraryView()
            }

            Tab(AsterionTab.downloads.label, systemImage: AsterionTab.downloads.systemImage, value: .downloads) {
                DownloadCenterView()
            }

            Tab(AsterionTab.account.label, systemImage: AsterionTab.account.systemImage, value: .account) {
                ProfileView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color.goldAccent)
        .toolbarVisibility(tabBarState.isVisible ? .visible : .hidden, for: .tabBar)
    }

    private func handlePendingContinueReadingRequest() {
        guard ContinueReadingStore.consumePendingLaunchRequest() else { return }
        tabBarState.selectedTab = .home
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .asterionContinueReadingRequested, object: nil)
        }
    }
}

private struct ContentAlertDestination: View {
    let target: ContentWatchTarget
    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var novel: Novel?
    @State private var failed = false

    var body: some View {
        Group {
            if target.kind == .anime {
                AnimeDetailView(title: AnimeTitle(slug: target.contentID, title: target.title,
                                                 japaneseTitle: nil, imageURL: nil, type: nil, episodeLabel: nil))
            } else if let novel {
                NovelDetailView(novel: novel) { dismiss() }
            } else if failed {
                ContentUnavailableView("Couldn't open this novel", systemImage: "wifi.exclamationmark")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            } else {
                ProgressView().tint(Color.goldAccent)
            }
        }
        .background { AsterionBackdrop() }
        .preferredColorScheme(.dark)
        .task {
            guard target.kind == .novel else { return }
            novel = await OfflineChapterStore.shared.loadCatalog().first { $0.id == target.contentID }
            if novel == nil { novel = try? await apiClient.fetchNovel(id: target.contentID) }
            failed = novel == nil
        }
    }
}

// MARK: - Handoff

/// Handoff contract shared with the macOS app (keep the keys in step).
private enum HandoffActivityType {
    static let reading = "cloud.cyberverse.asterion.reading"
    static let watching = "cloud.cyberverse.asterion.watching"
}

private enum HandoffDestination: Identifiable, Equatable {
    case reading(novelID: String, chapterID: String, line: Int, lineCount: Int?, progress: Double?, novelTitle: String)
    case watching(mediaType: MediaAccountType, contentID: String, title: String, imageURL: URL?)

    var id: String {
        switch self {
        case let .reading(novelID, chapterID, line, _, _, _): "reading-\(novelID)-\(chapterID)-\(line)"
        case let .watching(mediaType, contentID, _, _): "watching-\(mediaType.rawValue)-\(contentID)"
        }
    }

    init?(readingActivity activity: NSUserActivity) {
        let info = activity.userInfo ?? [:]
        guard let novelID = info["novelId"] as? String, !novelID.isEmpty,
              let chapterID = info["chapterId"] as? String, !chapterID.isEmpty else { return nil }
        let line = (info["line"] as? Int) ?? (info["line"] as? NSNumber)?.intValue ?? 0
        // Optional keys from newer senders; absent keys keep the plain index.
        let lineCount = ((info["lineCount"] as? NSNumber)?.intValue).flatMap { $0 > 0 ? $0 : nil }
        let progress = ((info["progress"] as? NSNumber)?.doubleValue).flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
        self = .reading(
            novelID: novelID,
            chapterID: chapterID,
            line: max(0, line),
            lineCount: lineCount,
            progress: progress,
            novelTitle: info["novelTitle"] as? String ?? ""
        )
    }

    init?(watchingActivity activity: NSUserActivity) {
        let info = activity.userInfo ?? [:]
        guard let rawType = info["mediaType"] as? String,
              let mediaType = MediaAccountType(rawValue: rawType),
              mediaType == .anime || mediaType == .movie,
              let contentID = info["contentId"] as? String, !contentID.isEmpty else { return nil }
        let imageURL = (info["imageURL"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        self = .watching(
            mediaType: mediaType,
            contentID: contentID,
            title: info["title"] as? String ?? activity.title ?? "",
            imageURL: imageURL
        )
    }
}

private struct HandoffDestinationView: View {
    let destination: HandoffDestination

    var body: some View {
        switch destination {
        case let .reading(novelID, chapterID, line, lineCount, progress, novelTitle):
            HandoffReadingDestination(
                novelID: novelID,
                chapterID: chapterID,
                line: line,
                lineCount: lineCount,
                progress: progress,
                novelTitle: novelTitle
            )
        case let .watching(mediaType, contentID, title, imageURL):
            // The detail page brings its own back control, which closes this cover.
            MediaDestinationView(mediaType: mediaType, contentID: contentID, title: title, imageURL: imageURL)
                .preferredColorScheme(.dark)
        }
    }
}

/// Loads the handed-off novel and chapter (cache first, then the API) and
/// opens the reader at the exact line.
private struct HandoffReadingDestination: View {
    let novelID: String
    let chapterID: String
    let line: Int
    let lineCount: Int?
    let progress: Double?
    let novelTitle: String

    @EnvironmentObject private var apiClient: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: (novel: Novel, chapter: Chapter, chapters: [Chapter])?
    @State private var failed = false

    var body: some View {
        Group {
            if let loaded {
                ReaderView(
                    initialChapter: loaded.chapter,
                    novel: loaded.novel,
                    allChapters: loaded.chapters,
                    shouldAutoResumeFromSavedProgress: false,
                    initialLine: line,
                    initialLineCount: lineCount,
                    initialLineProgress: progress
                )
            } else if failed {
                AsterionEmptyState(
                    symbol: "wifi.exclamationmark",
                    title: "Couldn't open this chapter",
                    message: "Check your connection and try again from the other device."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { closeToolbar }
            } else {
                VStack(spacing: 14) {
                    ProgressView().tint(Color.asterionInk)
                    Text(novelTitle.isEmpty ? "Opening chapter" : "Opening \(novelTitle)")
                        .font(.asterionReading(13.5))
                        .foregroundStyle(Color.asterionMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar { closeToolbar }
            }
        }
        .background { AsterionBackdrop() }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    @ToolbarContentBuilder
    private var closeToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
        }
    }

    private func load() async {
        guard loaded == nil else { return }
        var novel = await OfflineChapterStore.shared.loadCatalog().first { $0.id == novelID }
        if novel == nil { novel = try? await apiClient.fetchNovel(id: novelID) }

        var chapter = await OfflineChapterStore.shared.chapter(id: chapterID)
        if chapter?.content?.isEmpty != false, let fetched = try? await apiClient.fetchChapter(id: chapterID) {
            chapter = fetched
            await OfflineChapterStore.shared.cacheChapter(fetched)
        }

        guard let novel, let chapter else {
            failed = true
            return
        }

        var chapters = await OfflineChapterStore.shared.loadChapterList(novelId: novel.id)
        if chapters.isEmpty, let fetched = try? await apiClient.fetchAllChapters(novelId: novel.id) {
            await OfflineChapterStore.shared.saveChapterList(novelId: novel.id, chapters: fetched, mergeWithExisting: true)
            chapters = fetched
        }
        if !chapters.contains(where: { $0.id == chapter.id }) { chapters.insert(chapter, at: 0) }
        loaded = (novel, chapter, chapters)
    }
}
