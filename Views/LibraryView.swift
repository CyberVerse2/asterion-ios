import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.asterionBackground.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.goldAccent)
                    Text("Your Library")
                        .font(.title2)
                        .foregroundStyle(Color.asterionText)
                    Text("Saved novels and continue reading shortcuts appear here.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Library")
        }
    }
}
