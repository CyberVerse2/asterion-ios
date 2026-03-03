import SwiftUI

struct ReaderView: View {
    let chapter: Chapter
    let novelTitle: String
    @State private var fontSize: CGFloat = 20
    @State private var lineSpacing: CGFloat = 10
    @State private var sentLove = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.asterionBackground, Color(red: 0.1, green: 0.08, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(novelTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(chapter.title)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.asterionText)
                    Text(chapter.content)
                        .font(.system(size: fontSize, weight: .regular, design: .serif))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(Color.asterionText)
                        .textSelection(.enabled)

                    Button {
                        sentLove = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label(sentLove ? "Loved" : "Send Love", systemImage: sentLove ? "heart.fill" : "heart")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.goldAccent)
                }
                .padding()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("A+") { fontSize = min(fontSize + 1, 28) }
                Button("A-") { fontSize = max(fontSize - 1, 16) }
            }
        }
    }
}
