import AppKit
import SwiftUI

struct ScrollIndicatorHider: NSViewRepresentable {
    func makeNSView(context: Context) -> MarkerView {
        MarkerView()
    }

    func updateNSView(_ nsView: MarkerView, context: Context) {
        nsView.hideScrollIndicators()
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
            hideScrollIndicators()
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

                if scrollView.hasVerticalScroller,
                   !(scrollView.verticalScroller is InvisibleScroller)
                {
                    scrollView.verticalScroller = InvisibleScroller()
                    scrollView.hasVerticalScroller = true
                }

                if scrollView.hasHorizontalScroller,
                   !(scrollView.horizontalScroller is InvisibleScroller)
                {
                    scrollView.horizontalScroller = InvisibleScroller()
                    scrollView.hasHorizontalScroller = true
                }
            }

            for subview in view.subviews {
                hideScrollIndicators(in: subview)
            }
        }
    }

    final class InvisibleScroller: NSScroller {
        override func draw(_ dirtyRect: NSRect) {}
        override func drawKnob() {}
        override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
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
