import AppKit
import ClerkKit
import SwiftUI

@MainActor
final class AsterionAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
@MainActor
struct AsterionApp: App {
    private static let clerkKeychainService = "cloud.cyberverse.Asterion.clerk"

    @NSApplicationDelegateAdaptor(AsterionAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        AsterionFontRegistry.registerBundledFonts()
        let options = Clerk.Options(
            keychainConfig: .init(service: Self.clerkKeychainService)
        )
        Clerk.configure(
            publishableKey: "pk_test_cG9ldGljLWdhdG9yLTk3LmNsZXJrLmFjY291bnRzLmRldiQ",
            options: options
        )
    }

    var body: some Scene {
        WindowGroup("Asterion", id: "main") {
            ContentView()
                .environmentObject(model)
                .environment(Clerk.shared)
                .task { await model.start() }
        }
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

        WindowGroup("Anime Player", for: AnimePlayerRoute.self) { $route in
            if let route {
                AnimePlayerView(route: route)
            }
        }
        .defaultSize(width: 1_080, height: 700)
        .windowResizability(.contentMinSize)

        WindowGroup("Asterion Player", for: MoviePlayerRoute.self) { $route in
            if let route {
                MoviePlayerView(route: route)
            }
        }
        .defaultSize(width: 1_080, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        WindowGroup("Asterion Live", for: FootballPlayerRoute.self) { $route in
            if let route {
                FootballPlayerView(route: route)
            }
        }
        .defaultSize(width: 1_080, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)

        WindowGroup("Sign In to Asterion", id: "authentication") {
            AsterionAuthenticationView()
                .environment(Clerk.shared)
        }
        .defaultSize(width: 438, height: 548)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}

struct AsterionNavigationCommands: Commands {
    @FocusedBinding(\.asterionMode) private var mode
    @FocusedBinding(\.asterionSection) private var section
    @FocusedBinding(\.asterionAnimeSection) private var animeSection
    @FocusedBinding(\.asterionMovieSection) private var movieSection
    @FocusedBinding(\.asterionFootballSection) private var footballSection

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Novels") { mode = .novels }
                .keyboardShortcut("1", modifiers: [.command, .shift])
                .disabled(mode == nil)
            Button("Anime") { mode = .anime }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                .disabled(mode == nil)
            Button("Movies") { mode = .movies }
                .keyboardShortcut("3", modifiers: [.command, .shift])
                .disabled(mode == nil)
            Button("Football") { mode = .football }
                .keyboardShortcut("4", modifiers: [.command, .shift])
                .disabled(mode == nil)

            Divider()

            if mode == .anime {
                ForEach(Array(AnimeSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { animeSection = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(animeSection == nil)
                }
            } else if mode == .movies {
                ForEach(Array(MovieSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { movieSection = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(movieSection == nil)
                }
            } else if mode == .football {
                ForEach(Array(FootballSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { footballSection = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(footballSection == nil)
                }
            } else {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { section = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(section == nil)
                }
            }
        }
    }
}

extension FocusedValues {
    @Entry var asterionMode: Binding<AppMode>?
    @Entry var asterionSection: Binding<AppSection>?
    @Entry var asterionAnimeSection: Binding<AnimeSection>?
    @Entry var asterionMovieSection: Binding<MovieSection>?
    @Entry var asterionFootballSection: Binding<FootballSection>?
}
