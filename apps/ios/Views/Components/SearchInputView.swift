import Combine
import Inject
import SwiftUI

struct SearchInputView: View {
    @ObserveInjection var inject
    @Binding var text: String
    var placeholder: String = "Search"
    /// Focus the field as soon as it appears (dedicated search screens).
    var autoFocus: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFocused ? Color.asterionText : Color.asterionMuted)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.asterionReading(16))
                        .foregroundStyle(Color.asterionMuted)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text)
                    .font(.asterionReading(16, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { isFocused = false }
                    .accessibilityLabel(placeholder)
                    .task {
                        guard autoFocus else { return }
                        try? await Task.sleep(for: .milliseconds(350))
                        isFocused = true
                    }
            }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.asterionMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color.white.opacity(isFocused ? 0.09 : 0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(isFocused ? 0.2 : 0.08)))
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .enableInjection()
    }
}

struct DebouncedSearchModifier: ViewModifier {
    @Binding var text: String
    @Binding var debouncedText: String
    var delay: TimeInterval = 0.4

    @State private var debounceTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.onChange(of: text) { _, newValue in
            debounceTask?.cancel()
            debounceTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                debouncedText = newValue
            }
        }
    }
}

extension View {
    func debounceSearch(text: Binding<String>, debouncedText: Binding<String>, delay: TimeInterval = 0.4) -> some View {
        modifier(DebouncedSearchModifier(text: text, debouncedText: debouncedText, delay: delay))
    }
}
