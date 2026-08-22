import Combine
import ClerkKit
import ClerkKitUI
import Network
import SwiftUI

@MainActor
final class TabBarState: ObservableObject {
    @Published var isVisible = true
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
    Clerk.configure(publishableKey: "pk_test_cG9ldGljLWdhdG9yLTk3LmNsZXJrLmFjY291bnRzLmRldiQ")
    return true
}()

@main
struct AsterionApp: App {
    @StateObject private var authService = AuthService()
    @StateObject private var apiClient = APIClient()
    @StateObject private var tabBarState = TabBarState()
    @StateObject private var readingProgressService = ReadingProgressService()
    @StateObject private var networkMonitor = NetworkMonitor()

    init() {
        _ = _clerkConfigured

        let bg = UIColor(red: 0.051, green: 0.047, blue: 0.043, alpha: 1)
        let titleColor = UIColor(red: 0.91, green: 0.863, blue: 0.784, alpha: 1)

        let titleFont = makeNavigationSerifFont(size: 18, weight: .semibold)
        let largeTitleFont = makeNavigationSerifFont(size: 36, weight: .bold)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bg
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: titleColor,
            .font: titleFont,
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: titleColor,
            .font: largeTitleFont,
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(red: 0.42, green: 0.392, blue: 0.349, alpha: 1)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = bg
        tabAppearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    private func makeNavigationSerifFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let fallbackSystem = UIFont.systemFont(ofSize: size, weight: weight)
        switch weight {
        case .bold, .semibold, .heavy, .black:
            return UIFont(name: "Georgia-Bold", size: size) ?? fallbackSystem
        default:
            return UIFont(name: "Georgia", size: size) ?? fallbackSystem
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(authService)
                .environmentObject(apiClient)
                .environmentObject(tabBarState)
                .environmentObject(readingProgressService)
                .environmentObject(networkMonitor)
                .environment(Clerk.shared)
                .preferredColorScheme(.dark)
                .task {
                    authService.startClerkSessionObserver(using: apiClient)
                    await authService.syncClerkSession()
                    apiClient.setSessionToken(authService.sessionToken)
                    await authService.syncUserProfileToBackend(using: apiClient)
                    readingProgressService.configure(apiClient: apiClient)
                    await readingProgressService.flushQueue()
                }
                .onChange(of: networkMonitor.isConnected) { _, isConnected in
                    guard isConnected else { return }
                    Task {
                        apiClient.setSessionToken(authService.sessionToken)
                        await readingProgressService.flushQueue()
                    }
                }
        }
    }
}

enum AsterionTab: String, CaseIterable {
    case discover
    case rankings
    case library
    case profile

    var label: String {
        switch self {
        case .discover:  return "Discover"
        case .rankings:  return "Rankings"
        case .library:   return "Library"
        case .profile:   return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .discover:  return "sparkles"
        case .rankings:  return "crown"
        case .library:   return "books.vertical"
        case .profile:   return "person.crop.circle"
        }
    }
}

struct RootTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var tabBarState: TabBarState
    @State private var selectedTab: AsterionTab = .discover

    var body: some View {
        Group {
            #if targetEnvironment(macCatalyst)
            DesktopRootView(selectedTab: $selectedTab)
            #else
            phoneTabView
            #endif
        }
        .onAppear { handlePendingContinueReadingRequest() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handlePendingContinueReadingRequest()
        }
    }

    private var phoneTabView: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(AsterionTab.discover)
                .tabItem {
                    Label(AsterionTab.discover.label, systemImage: AsterionTab.discover.systemImage)
                }

            RankingView()
                .tag(AsterionTab.rankings)
                .tabItem {
                    Label(AsterionTab.rankings.label, systemImage: AsterionTab.rankings.systemImage)
                }

            LibraryView()
                .tag(AsterionTab.library)
                .tabItem {
                    Label(AsterionTab.library.label, systemImage: AsterionTab.library.systemImage)
                }

            ProfileView()
                .tag(AsterionTab.profile)
                .tabItem {
                    Label(AsterionTab.profile.label, systemImage: AsterionTab.profile.systemImage)
                }
        }
        .tint(Color.goldAccent)
        .toolbarVisibility(tabBarState.isVisible ? .visible : .hidden, for: .tabBar)
    }

    private func handlePendingContinueReadingRequest() {
        guard ContinueReadingStore.consumePendingLaunchRequest() else { return }
        selectedTab = .discover
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .asterionContinueReadingRequested, object: nil)
        }
    }
}

#if targetEnvironment(macCatalyst)
private struct DesktopRootView: View {
    @Binding var selectedTab: AsterionTab

    var body: some View {
        VStack(spacing: 0) {
            desktopTopBar

            selectedTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.asterionBackground.ignoresSafeArea())
        .tint(Color.goldAccent)
    }

    private var desktopTopBar: some View {
        HStack(spacing: 24) {
            Text("Asterion")
                .font(.asterionSerif(30, weight: .semibold))
                .foregroundStyle(Color.asterionText)
                .frame(minWidth: 160, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(AsterionTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.label, systemImage: tab.systemImage)
                            .font(.asterionSerif(17, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? Color.goldAccent : Color.asterionReaderText)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedTab == tab ? Color.goldAccent.opacity(0.13) : Color.asterionCard.opacity(0.35))
                                    .stroke(selectedTab == tab ? Color.goldAccent.opacity(0.35) : Color.asterionBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 20)
        .background(
            Color.asterionBackground
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.asterionBorder)
                        .frame(height: 1)
                }
        )
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .discover:
            HomeView()
        case .rankings:
            RankingView()
        case .library:
            LibraryView()
        case .profile:
            ProfileView()
        }
    }
}
#endif
