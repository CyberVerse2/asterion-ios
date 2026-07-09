import AppKit
import SwiftUI

struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> MarkerView {
        MarkerView()
    }

    func updateNSView(_ nsView: MarkerView, context: Context) {
        nsView.scheduleScrollIndicatorPasses()
    }

    final class MarkerView: NSView {
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if let window {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didUpdateNotification,
                    object: window
                )
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidUpdate),
                    name: NSWindow.didUpdateNotification,
                    object: window
                )
            }
            scheduleScrollIndicatorPasses()
        }

        override func layout() {
            super.layout()
            hideScrollIndicators()
        }

        func hideScrollIndicators() {
            DispatchQueue.main.async { [weak self] in
                self?.hideScrollIndicatorsImmediately()
            }
        }

        func scheduleScrollIndicatorPasses() {
            for delay in [0.0, 0.15, 0.75, 2.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.hideScrollIndicatorsImmediately()
                }
            }
        }

        @objc private func windowDidUpdate(_ notification: Notification) {
            hideScrollIndicatorsImmediately()
        }

        private func hideScrollIndicatorsImmediately() {
            guard let contentView = window?.contentView else { return }
            Self.hideScrollIndicators(in: contentView)
        }

        private static func hideScrollIndicators(in view: NSView) {
            if let scrollView = view as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.hasVerticalScroller = false
                scrollView.hasHorizontalScroller = false
            }

            for subview in view.subviews {
                hideScrollIndicators(in: subview)
            }
        }
    }

}

extension View {
    func hidingScrollIndicators() -> some View {
        scrollIndicators(.hidden)
            .background {
                ScrollIndicatorHider()
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
