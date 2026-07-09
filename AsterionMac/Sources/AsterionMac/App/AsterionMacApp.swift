import AppKit
import ClerkKit
import SwiftUI

@MainActor
final class AsterionAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.removeSidebarToggle()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.removeSidebarToggle()
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        removeSidebarToggle()
    }

    private func removeSidebarToggle() {
        for window in NSApp.windows {
            guard let toolbar = window.toolbar else { continue }
            for index in toolbar.items.indices.reversed() {
                let item = toolbar.items[index]
                let action = item.action.map(NSStringFromSelector) ?? ""
                let details = [
                    item.itemIdentifier.rawValue,
                    item.label,
                    item.paletteLabel,
                    item.toolTip ?? "",
                    action,
                ].joined(separator: " ").lowercased()
                if details.contains("sidebar") {
                    toolbar.removeItem(at: index)
                }
            }
        }
    }
}

@main
@MainActor
struct AsterionMacApp: App {
    private static let clerkKeychainService = "cloud.cyberverse.AsterionMac.clerk"

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
        .defaultSize(width: 1240, height: 780)
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
