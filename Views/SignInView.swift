import ClerkKitUI
import SwiftUI

struct SignInView: View {
    @State private var showAuth = false

    var body: some View {
        ZStack {
            Color.asterionBackground.ignoresSafeArea()
            MazePatternView()
                .ignoresSafeArea()
                .opacity(0.4)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.goldAccent.opacity(0.12), .clear],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)

                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Color.goldAccent)
                    }

                    Text("Asterion")
                        .font(.asterionSerif(36, weight: .light))
                        .foregroundStyle(Color.asterionText)
                        .tracking(4)

                    Text("YOUR READING JOURNEY AWAITS")
                        .font(.asterionMono(10))
                        .foregroundStyle(Color.asterionDim)
                        .tracking(3)
                }

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        showAuth = true
                    } label: {
                        Text("Sign In")
                            .font(.asterionSerif(16, weight: .medium))
                            .foregroundStyle(Color.asterionBackground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.goldAccent)
                            )
                    }

                    Button {
                        showAuth = true
                    } label: {
                        Text("Create Account")
                            .font(.asterionSerif(16, weight: .medium))
                            .foregroundStyle(Color.goldAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.clear)
                                    .stroke(Color.asterionBorder, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showAuth) {
            AuthView()
        }
    }
}
