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
                .preferredColorScheme(.light)
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
                    .preferredColorScheme(.light)
            }
        }
        .defaultSize(width: 840, height: 900)

        WindowGroup("Sign In to Asterion", id: "authentication") {
            AsterionAuthenticationView()
                .environment(Clerk.shared)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 438, height: 548)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .preferredColorScheme(.light)
        }
    }
}

struct AsterionNavigationCommands: Commands {
    @FocusedBinding(\.asterionSection) private var section

    var body: some Commands {
        CommandMenu("Navigate") {
            ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { section = item }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(section == nil)
            }
        }
    }
}

extension FocusedValues {
    @Entry var asterionSection: Binding<AppSection>?
}
