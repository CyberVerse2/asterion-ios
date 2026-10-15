import Combine
import Inject
import SwiftUI

struct SearchInputView: View {
    @ObserveInjection var inject
    @Binding var text: String
    var placeholder: String = "Search"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.asterionDisplay(24, weight: .regular))
                        .foregroundStyle(Color.asterionMuted)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text)
                    .font(.asterionDisplay(24, weight: .medium))
                    .foregroundStyle(Color.asterionText)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit { isFocused = false }
            }

            if !text.isEmpty {
                Button("Clear") { text = "" }
                    .font(.asterionReading(14, weight: .medium))
                    .foregroundStyle(Color.asterionMuted)
                    .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isFocused ? Color.asterionInk : Color.asterionText.opacity(0.28))
                .frame(height: isFocused ? 1.5 : 1)
        }
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
