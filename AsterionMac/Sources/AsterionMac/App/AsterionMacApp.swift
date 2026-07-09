import AppKit
import ClerkKit
import SwiftUI

@MainActor
final class AsterionAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowToolbarDidChange(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toolbarWillAddItem(_:)),
            name: NSToolbar.willAddItemNotification,
            object: nil
        )
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
            self.removeSidebarToggles()
        }
    }

    @objc private func windowToolbarDidChange(_ notification: Notification) {
        removeSidebarToggles()
    }

    @objc private func toolbarWillAddItem(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.removeSidebarToggles()
        }
    }

    private func removeSidebarToggles() {
        for window in NSApp.windows {
            guard let toolbar = window.toolbar else { continue }
            for index in toolbar.items.indices.reversed() {
                let item = toolbar.items[index]
                if containsSidebarToggle(item) {
                    toolbar.removeItem(at: index)
                }
            }
        }
    }

    private func containsSidebarToggle(_ item: NSToolbarItem) -> Bool {
        if item.itemIdentifier == .toggleSidebar {
            return true
        }
        if let group = item as? NSToolbarItemGroup,
           group.subitems.contains(where: containsSidebarToggle) {
            return true
        }
        let action = item.action.map(NSStringFromSelector) ?? ""
        return [
            item.itemIdentifier.rawValue,
            item.label,
            item.paletteLabel,
            item.toolTip ?? "",
            action,
        ].joined(separator: " ").localizedCaseInsensitiveContains("sidebar")
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
        .defaultSize(width: 1240, height: 780)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .sidebar) {}
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
