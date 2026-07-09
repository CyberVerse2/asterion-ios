import SwiftUI

enum AsterionMotion {
    static let press = Animation.easeOut(duration: 0.12)
    static let hover = Animation.easeOut(duration: 0.16)
    static let reveal = Animation.easeOut(duration: 0.22)
    static let navigation = Animation.spring(duration: 0.28, bounce: 0.06)
}

struct AsterionPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.975)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : AsterionMotion.press, value: configuration.isPressed)
    }
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
