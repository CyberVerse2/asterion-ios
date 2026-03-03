import Combine
import Inject
import SwiftUI

struct SearchInputView: View {
    @ObserveInjection var inject
    @Binding var text: String
    var placeholder: String = "Search..."

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.asterionDim)

            TextField(placeholder, text: $text)
                .font(.asterionSerif(14))
                .foregroundStyle(Color.asterionText)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.asterionDim)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.102, green: 0.094, blue: 0.086))
                .stroke(isFocused ? Color.asterionBorderHover : Color.asterionBorder, lineWidth: 1)
        )
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
