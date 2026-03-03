import SwiftUI

@main
struct AsterionApp: App {
    @StateObject private var authService = AuthService()
    @StateObject private var apiClient = APIClient()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(authService)
                .environmentObject(apiClient)
                .preferredColorScheme(.dark)
                .task {
                    await authService.restoreSession()
                    apiClient.setSessionToken(authService.sessionToken)
                }
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            RankingView()
                .tabItem { Label("Ranking", systemImage: "chart.bar.fill") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
        .tint(Color.goldAccent)
    }
}
