import SwiftUI

struct ContentModePicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppMode

    private let indicatorInset: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let modes = AppMode.allCases
            let segmentWidth = geometry.size.width / CGFloat(modes.count)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .frame(
                        width: segmentWidth - (indicatorInset * 2),
                        height: geometry.size.height - (indicatorInset * 2)
                    )
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .offset(
                        x: indicatorInset + (segmentWidth * CGFloat(selectedIndex(in: modes))),
                        y: indicatorInset
                    )

                HStack(spacing: 0) {
                    ForEach(modes, id: \.self) { mode in
                        Button {
                            guard selection != mode else { return }
                            selection = mode
                        } label: {
                            Text(mode.title)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selection == mode ? .primary : .secondary)
                        .accessibilityAddTraits(selection == mode ? .isSelected : [])
                        .accessibilityValue(selection == mode ? "Selected" : "")
                    }
                }
            }
        }
        .frame(height: 36)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selection)
    }

    private func selectedIndex(in modes: [AppMode]) -> Int {
        modes.firstIndex(of: selection) ?? 0
    }
}
