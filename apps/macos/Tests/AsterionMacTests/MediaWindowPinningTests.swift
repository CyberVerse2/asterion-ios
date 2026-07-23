import AppKit
import Testing
@testable import AsterionMac

@MainActor
struct MediaWindowPinningTests {
    @Test func pinningRaisesOnlyTheManagedWindow() throws {
        let managedWindow = NSWindow()
        let otherWindow = NSWindow()
        let contentView = try #require(managedWindow.contentView)
        let marker = MediaWindowLevelBridge.MarkerView()

        contentView.addSubview(marker)
        marker.setPinned(true)

        #expect(managedWindow.level == .floating)
        #expect(otherWindow.level == .normal)

        marker.setPinned(false)

        #expect(managedWindow.level == .normal)
    }

    @Test func removingTheBridgeRestoresTheOriginalWindowLevel() throws {
        let window = NSWindow()
        window.level = .modalPanel
        let contentView = try #require(window.contentView)
        let marker = MediaWindowLevelBridge.MarkerView()

        contentView.addSubview(marker)
        marker.setPinned(true)
        #expect(window.level == .floating)

        marker.removeFromSuperview()

        #expect(window.level == .modalPanel)
    }
}
