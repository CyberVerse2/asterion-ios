import SwiftUI

enum AsterionMotion {
    static let hover = Animation.easeOut(duration: 0.16)
    static let reveal = Animation.easeOut(duration: 0.22)
    static let navigation = Animation.spring(duration: 0.28, bounce: 0.06)
    static let sidebar = Animation.easeInOut(duration: 0.22)
}

private struct AsterionHoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion || !isHovering ? 1 : 1.018)
            .offset(y: reduceMotion || !isHovering ? 0 : -3)
            .shadow(
                color: .black.opacity(reduceMotion || !isHovering ? 0 : 0.10),
                radius: reduceMotion || !isHovering ? 0 : 12,
                y: reduceMotion || !isHovering ? 0 : 7
            )
            .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension View {
    func asterionHoverLift() -> some View {
        modifier(AsterionHoverLift())
    }
}
