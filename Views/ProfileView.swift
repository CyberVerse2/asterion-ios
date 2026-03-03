import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var apiClient: APIClient
    @State private var statusMessage = "Signed out"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.asterionBackground.ignoresSafeArea()
                VStack(spacing: 18) {
                    if let user = authService.currentUser {
                        Text(user.username ?? "Reader")
                            .font(.title2)
                            .foregroundStyle(Color.asterionText)
                        Text(user.email ?? "No email")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }

                    SignInWithAppleButton(.signIn) { _ in
                    } onCompletion: { result in
                        Task {
                            await handleAppleResult(result)
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 46)

                    Button("Sign Out") {
                        authService.signOut()
                        statusMessage = "Signed out"
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Profile")
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            statusMessage = error.localizedDescription
        case .success(let auth):
            guard let credentials = auth.credential as? ASAuthorizationAppleIDCredential else {
                statusMessage = "Invalid Apple credentials"
                return
            }
            let tokenData = credentials.identityToken ?? Data()
            let token = String(data: tokenData, encoding: .utf8) ?? "missing-token"
            do {
                let response = try await apiClient.authenticateWithApple(
                    identityToken: token,
                    appleUserId: credentials.user,
                    email: credentials.email
                )
                authService.persistSession(token: response.0, user: response.1)
                apiClient.setSessionToken(response.0)
                statusMessage = "Signed in"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
