import SwiftUI

struct ContentModePicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @Binding var selection: AppMode

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Button {
                        guard selection != mode else { return }
                        selection = mode
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selection == mode ? .primary : .secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .modifier(
                                SelectedModeGlass(
                                    isSelected: selection == mode,
                                    namespace: glassNamespace
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Show \(mode.title)")
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(selection == mode ? .isSelected : [])
                    .accessibilityValue(selection == mode ? "Selected" : "")
                }
            }
        }
        .frame(height: 36)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: selection)
    }
}

private struct SelectedModeGlass: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("mode-selection", in: namespace)
                .glassEffectTransition(.matchedGeometry)
        } else {
            content
        }
    }
}
