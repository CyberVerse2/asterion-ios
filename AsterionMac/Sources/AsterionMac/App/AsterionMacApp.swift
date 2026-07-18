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
    private static let clerkPublishableKeyInfoKey = "AsterionClerkPublishableKey"

    private static var clerkPublishableKey: String {
        #if DEBUG
        "pk_test_cG9ldGljLWdhdG9yLTk3LmNsZXJrLmFjY291bnRzLmRldiQ"
        #else
        guard let key = Bundle.main.object(forInfoDictionaryKey: clerkPublishableKeyInfoKey) as? String,
              key.hasPrefix("pk_live_") else {
            fatalError(
                "Release builds require a production Clerk publishable key in the "
                    + "\(clerkPublishableKeyInfoKey) Info.plist entry."
            )
        }
        return key
        #endif
    }

    @NSApplicationDelegateAdaptor(AsterionAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        AsterionFontRegistry.registerBundledFonts()
        let options = Clerk.Options(
            keychainConfig: .init(service: Self.clerkKeychainService)
        )
        Clerk.configure(
            publishableKey: Self.clerkPublishableKey,
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
                    .environmentObject(model)
            }
        }
        .defaultSize(width: 1_080, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .asterionMediaWindowPlacement()

        WindowGroup("Asterion Player", for: MoviePlayerRoute.self) { $route in
            if let route {
                MoviePlayerView(route: route)
                    .environmentObject(model)
            }
        }
        .defaultSize(width: 1_080, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .asterionMediaWindowPlacement()

        WindowGroup("Asterion Live", for: FootballPlayerRoute.self) { $route in
            if let route {
                FootballPlayerView(route: route)
            }
        }
        .defaultSize(width: 1_080, height: 700)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .asterionMediaWindowPlacement()

        Window("Sign In to Asterion", id: "authentication") {
            AsterionAuthenticationView()
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
    @FocusedBinding(\.asterionMode) private var mode
    @FocusedBinding(\.asterionSection) private var section
    @FocusedBinding(\.asterionAnimeSection) private var animeSection
    @FocusedBinding(\.asterionMovieSection) private var movieSection
    @FocusedBinding(\.asterionFootballSection) private var footballSection
    @FocusedBinding(\.asterionShowsAccount) private var showsAccount

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Novels") {
                mode = .novels
                showsAccount = false
            }
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(mode == nil)
            Button("Anime") {
                mode = .anime
                showsAccount = false
            }
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(mode == nil)
            Button("Movies") {
                mode = .movies
                showsAccount = false
            }
                .keyboardShortcut("3", modifiers: [.command, .option])
                .disabled(mode == nil)
            Button("Football") {
                mode = .football
                showsAccount = false
            }
                .keyboardShortcut("4", modifiers: [.command, .option])
                .disabled(mode == nil)

            Divider()

            if mode == .anime {
                ForEach(Array(AnimeSection.allCases.enumerated()), id: \.element) { index, item in
                    if index < 9 {
                        Button(item.title) {
                            animeSection = item
                            showsAccount = false
                        }
                            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                            .disabled(animeSection == nil)
                    } else {
                        Button(item.title) {
                            animeSection = item
                            showsAccount = false
                        }
                            .disabled(animeSection == nil)
                    }
                }
            } else if mode == .movies {
                ForEach(Array(MovieSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) {
                        movieSection = item
                        showsAccount = false
                    }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(movieSection == nil)
                }
            } else if mode == .football {
                ForEach(Array(FootballSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) {
                        footballSection = item
                        showsAccount = false
                    }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(footballSection == nil)
                }
            } else {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) {
                        section = item
                        showsAccount = false
                    }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                        .disabled(section == nil)
                }
            }

            Divider()

            Button("Account") { showsAccount = true }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(showsAccount == nil)
        }
    }
}

extension FocusedValues {
    @Entry var asterionMode: Binding<AppMode>?
    @Entry var asterionSection: Binding<AppSection>?
    @Entry var asterionAnimeSection: Binding<AnimeSection>?
    @Entry var asterionMovieSection: Binding<MovieSection>?
    @Entry var asterionFootballSection: Binding<FootballSection>?
    @Entry var asterionShowsAccount: Binding<Bool>?
}
