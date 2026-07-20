import SwiftUI

extension View {
    func hidingScrollIndicators() -> some View {
        scrollIndicators(.never, axes: [.horizontal, .vertical])
    }
}
