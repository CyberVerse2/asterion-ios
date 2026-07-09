import ClerkKit
import ClerkKitUI
import SwiftUI

struct AccountSummaryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Label(model.isSignedIn ? "Profile" : "Sign In", systemImage: "person.crop.circle")
                .font(.headline)
        }
        .listStyle(.inset)
        .navigationTitle("Account")
    }
}

struct AccountView: View {
    @EnvironmentObject private var model: AppModel
    @State private var presentsAuthentication = false

    var body: some View {
        VStack(spacing: 24) {
            if let user = model.signedInUser {
                profile(user)
            } else {
                signedOut
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(Color.asterionBackground)
        .sheet(isPresented: $presentsAuthentication) {
            AuthView()
                .environment(Clerk.shared)
                .frame(minWidth: 460, minHeight: 620)
        }
    }

    private func profile(_ user: AppModel.SignedInUser) -> some View {
        VStack(spacing: 18) {
            AsyncImage(url: user.imageURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())

            Text(user.name)
                .font(.asterionSerif(30, weight: .semibold))
                .foregroundStyle(Color.asterionText)
            if let email = user.email {
                Text(email)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("\(model.libraryNovelIDs.count) saved \(model.libraryNovelIDs.count == 1 ? "novel" : "novels")")
                .font(.headline)
                .foregroundStyle(Color.asterionGold)

            if let error = model.accountError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Sign Out") {
                Task { await model.signOut() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var signedOut: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.circle")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(Color.asterionGold)
            Text("Keep your place")
                .font(.asterionSerif(32, weight: .semibold))
                .foregroundStyle(Color.asterionText)
            Text("Sign in to sync your library and reading progress across Asterion.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let error = model.accountError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Sign In or Create Account") {
                presentsAuthentication = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.asterionGold)
            .controlSize(.large)
        }
    }
}
