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

    var body: some View {
        Group {
            appTabView
        }
        .onAppear { handlePendingContinueReadingRequest() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handlePendingContinueReadingRequest()
        }
        .fullScreenCover(isPresented: onboardingPresentation) {
            InterestOnboardingView {
                hasCompletedOnboarding = true
            }
        }
        .fullScreenCover(item: $contentNotifications.openTarget) { target in
            NavigationStack { ContentAlertDestination(target: target) }
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
                HomeView(mode: .home)
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
        .task {
            guard target.kind == .novel else { return }
            novel = await OfflineChapterStore.shared.loadCatalog().first { $0.id == target.contentID }
            if novel == nil { novel = try? await apiClient.fetchNovel(id: target.contentID) }
            failed = novel == nil
        }
    }
}
