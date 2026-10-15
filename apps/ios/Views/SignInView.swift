import ClerkKit
import ClerkKitUI
import SwiftUI

struct SignInView: View {
    @State private var showAuth = false

    var body: some View {
        ZStack {
            AsterionBackdrop()

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    AsterionMark(size: 22)
                    Text("Asterion")
                        .font(.asterionDisplay(40, weight: .medium))
                        .foregroundStyle(Color.asterionText)
                        .tracking(-0.6)

                    Text("Sign in to keep your library with you.")
                        .font(.asterionReading(17))
                        .foregroundStyle(Color.asterionSynopsis)
                }
                .frame(maxWidth: 420, alignment: .leading)
                .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showAuth = true
                    } label: {
                        Text("Sign in")
                            .font(.asterionReading(16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(AsterionFilledButtonStyle())

                    Button {
                        showAuth = true
                    } label: {
                        Text("Create account")
                            .font(.asterionReading(16, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(AsterionOutlineButtonStyle())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showAuth) {
            AuthView()
                .environment(Clerk.shared)
        }
    }
}
