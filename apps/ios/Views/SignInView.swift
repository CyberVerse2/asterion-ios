import ClerkKit
import ClerkKitUI
import SwiftUI

struct SignInView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var pageHorizontalPadding: CGFloat { AsterionLayout.pagePadding(horizontalSizeClass) }

    var body: some View {
        ZStack {
            AsterionBackdrop()

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    AsterionEyebrow(text: "Asterion")

                    Text("Sign in")
                        .font(.asterionTitle(28, weight: .heavy))
                        .foregroundStyle(Color.asterionText)
                        .accessibilityAddTraits(.isHeader)

                    Text("Keep your library, reading progress, and downloads with you on every device.")
                        .font(.asterionReading(14.5))
                        .foregroundStyle(Color.asterionMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                AuthView(isDismissable: false)
                    .environment(Clerk.shared)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .asterionPanel(cornerRadius: 16)
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
    }
}
