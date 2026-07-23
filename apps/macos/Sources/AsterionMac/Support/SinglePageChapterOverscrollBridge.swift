import AppKit
import SwiftUI

struct ChapterOverscrollGate {
    private static let wheelPause: TimeInterval = 0.45

    private(set) var reachedBottomAt: TimeInterval?

    mutating func update(isAtBottom: Bool, timestamp: TimeInterval) {
        if isAtBottom {
            reachedBottomAt = reachedBottomAt ?? timestamp
        } else {
            reachedBottomAt = nil
        }
    }

    mutating func shouldAdvance(
        isScrollingDown: Bool,
        beganGesture: Bool,
        isMomentum: Bool,
        timestamp: TimeInterval
    ) -> Bool {
        guard isScrollingDown,
              !isMomentum,
              let reachedBottomAt
        else {
            return false
        }

        let isSeparateWheelStep = timestamp - reachedBottomAt >= Self.wheelPause
        guard beganGesture || isSeparateWheelStep else { return false }
        self.reachedBottomAt = nil
        return true
    }
}

struct SinglePageChapterOverscrollBridge: NSViewRepresentable {
    let canAdvance: Bool
    let onAdvance: () -> Void

    func makeNSView(context: Context) -> OverscrollTrackingView {
        OverscrollTrackingView(canAdvance: canAdvance, onAdvance: onAdvance)
    }

    func updateNSView(_ view: OverscrollTrackingView, context: Context) {
        view.canAdvance = canAdvance
        view.onAdvance = onAdvance
        view.connectToScrollViewIfNeeded()
    }

    static func dismantleNSView(_ view: OverscrollTrackingView, coordinator: Void) {
        view.disconnect()
    }
}

final class OverscrollTrackingView: NSView {
    var canAdvance: Bool
    var onAdvance: () -> Void

    private weak var trackedScrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?
    private var eventMonitor: Any?
    private var gate = ChapterOverscrollGate()

    init(canAdvance: Bool, onAdvance: @escaping () -> Void) {
        self.canAdvance = canAdvance
        self.onAdvance = onAdvance
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            disconnect()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.connectToScrollViewIfNeeded()
            }
        }
    }

    func connectToScrollViewIfNeeded() {
        guard trackedScrollView == nil else { return }

        var ancestor = superview
        var enclosingScrollView: NSScrollView?
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                enclosingScrollView = scrollView
                break
            }
            ancestor = view.superview
        }
        guard let scrollView = enclosingScrollView else { return }

        trackedScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBottomState()
            }
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheel(event)
            return event
        }
        updateBottomState()
    }

    func disconnect() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        trackedScrollView = nil
        gate = ChapterOverscrollGate()
    }

    private func updateBottomState(timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let scrollView = trackedScrollView,
              let documentView = scrollView.documentView
        else {
            return
        }
        let isAtBottom = scrollView.documentVisibleRect.maxY >= documentView.bounds.maxY - 2
        gate.update(isAtBottom: isAtBottom, timestamp: timestamp)
    }

    private func handleScrollWheel(_ event: NSEvent) {
        guard canAdvance,
              let scrollView = trackedScrollView,
              event.window === window,
              scrollView.frame.contains(scrollView.superview?.convert(event.locationInWindow, from: nil) ?? .zero)
        else {
            return
        }

        updateBottomState(timestamp: event.timestamp)
        let beganGesture = event.phase.contains(.began)
        let isMomentum = !event.momentumPhase.isEmpty
        if gate.shouldAdvance(
            isScrollingDown: event.scrollingDeltaY < 0,
            beganGesture: beganGesture,
            isMomentum: isMomentum,
            timestamp: event.timestamp
        ) {
            onAdvance()
        }
    }
}
