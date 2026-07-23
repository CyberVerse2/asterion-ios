import SwiftUI

private struct EdgeSwipeBackModifier: ViewModifier {
    let onBack: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onEnded { value in
                        let startedFromLeftEdge = value.startLocation.x <= 24
                        let movedRightEnough = value.translation.width >= 90
                        let mostlyHorizontal = abs(value.translation.height) < 80
                        guard startedFromLeftEdge, movedRightEnough, mostlyHorizontal else { return }
                        onBack()
                    }
            )
    }
}

extension View {
    func edgeSwipeToDismiss(onBack: @escaping () -> Void) -> some View {
        modifier(EdgeSwipeBackModifier(onBack: onBack))
    }
}
