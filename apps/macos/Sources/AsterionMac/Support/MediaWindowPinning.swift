import AppKit
import SwiftUI

struct MediaWindowPinButton: View {
    @Binding var isPinned: Bool

    var body: some View {
        Button {
            isPinned.toggle()
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPinned ? Color.asterionAccent : .white.opacity(0.72))
        .help(isPinned ? "Stop Keeping Window on Top" : "Keep Window on Top")
        .accessibilityLabel(isPinned ? "Stop Keeping Window on Top" : "Keep Window on Top")
        .accessibilityValue(isPinned ? "On" : "Off")
    }
}

struct MediaWindowLevelBridge: NSViewRepresentable {
    let isPinned: Bool

    func makeNSView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.setPinned(isPinned)
        return view
    }

    func updateNSView(_ view: MarkerView, context: Context) {
        view.setPinned(isPinned)
    }

    static func dismantleNSView(_ view: MarkerView, coordinator: Void) {
        view.restoreWindowLevel()
    }

    final class MarkerView: NSView {
        private(set) var isPinned = false
        private weak var managedWindow: NSWindow?
        private var originalLevel: NSWindow.Level?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow !== window {
                restoreWindowLevel()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            managedWindow = window
            originalLevel = window.level
            applyWindowLevel()
        }

        func setPinned(_ isPinned: Bool) {
            guard self.isPinned != isPinned else { return }
            self.isPinned = isPinned
            applyWindowLevel()
        }

        func restoreWindowLevel() {
            if let managedWindow, let originalLevel {
                managedWindow.level = originalLevel
            }
            managedWindow = nil
            originalLevel = nil
        }

        private func applyWindowLevel() {
            guard let managedWindow else { return }
            managedWindow.level = isPinned ? .floating : originalLevel ?? .normal
        }
    }
}

extension View {
    func mediaWindowPinning(isPinned: Bool) -> some View {
        background {
            MediaWindowLevelBridge(isPinned: isPinned)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
