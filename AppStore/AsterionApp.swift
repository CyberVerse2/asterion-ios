import Combine
import ClerkKit
import ClerkKitUI
import SwiftUI

@MainActor
final class TabBarState: ObservableObject {
    @Published var isVisible = true
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

    init() {
        _ = _clerkConfigured

        let bg = UIColor(red: 0.051, green: 0.047, blue: 0.043, alpha: 1)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bg
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor(red: 0.91, green: 0.863, blue: 0.784, alpha: 1)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(red: 0.91, green: 0.863, blue: 0.784, alpha: 1)]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(red: 0.42, green: 0.392, blue: 0.349, alpha: 1)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = bg
        tabAppearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(authService)
                .environmentObject(apiClient)
                .environmentObject(tabBarState)
                .environment(Clerk.shared)
                .preferredColorScheme(.dark)
                .task {
                    await authService.syncClerkSession()
                    apiClient.setSessionToken(authService.sessionToken)
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
    @EnvironmentObject private var tabBarState: TabBarState
    @State private var selectedTab: AsterionTab = .discover

    var body: some View {
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
}
