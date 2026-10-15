import AppKit
import SwiftUI

@MainActor
final class DeviceAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct AsterionDeviceApp: App {
    @NSApplicationDelegateAdaptor(DeviceAppDelegate.self) private var appDelegate
    @State private var controller = BuildController()

    var body: some Scene {
        Window("Asterion Device", id: "main") {
            ContentView(controller: controller)
        }
        .defaultSize(width: 760, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
