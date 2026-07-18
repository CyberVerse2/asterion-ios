import SwiftUI

struct ContentModePicker: View {
    @Binding var selection: AppMode
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Button {
                        guard selection != mode else { return }
                        withAnimation(.smooth(duration: 0.3)) {
                            selection = mode
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == mode ? .primary : .secondary)
                    .background {
                        if selection == mode {
                            Capsule()
                                .fill(.clear)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .glassEffectID("active-mode", in: glassNamespace)
                                .matchedGeometryEffect(id: "active-mode-position", in: glassNamespace)
                        }
                    }
                    .accessibilityAddTraits(selection == mode ? .isSelected : [])
                    .accessibilityValue(selection == mode ? "Selected" : "")
                }
            }
            .padding(4)
            .overlay {
                Capsule()
                    .stroke(.primary.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(.smooth(duration: 0.3), value: selection)
    }
}
