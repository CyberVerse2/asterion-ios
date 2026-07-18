import SwiftUI

struct ContentModePicker: View {
    @Binding var selection: AppMode

    private let trackInset: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let modes = AppMode.allCases
            let segmentWidth = (geometry.size.width - (trackInset * 2)) / CGFloat(modes.count)

            ZStack(alignment: .leading) {
                GlassEffectContainer(spacing: 0) {
                    Capsule()
                        .fill(.clear)
                        .frame(
                            width: segmentWidth,
                            height: geometry.size.height - (trackInset * 2)
                        )
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .offset(
                            x: trackInset + (segmentWidth * CGFloat(selectedIndex(in: modes))),
                            y: trackInset
                        )
                }

                HStack(spacing: 0) {
                    ForEach(modes, id: \.self) { mode in
                        Button {
                            guard selection != mode else { return }
                            withAnimation(.smooth(duration: 0.3)) {
                                selection = mode
                            }
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
                    .padding(.horizontal, trackInset)
                }
            }
        }
        .frame(height: 42)
        .animation(.smooth(duration: 0.3), value: selection)
    }

    private func selectedIndex(in modes: [AppMode]) -> Int {
        modes.firstIndex(of: selection) ?? 0
    }
}
