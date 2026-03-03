import ClerkKit
import Combine
import Foundation

@MainActor
final class AuthService: NSObject, ObservableObject {
    @Published var currentUser: User?
    @Published var sessionToken: String?
    @Published var authError: String?

    private let keychain = KeychainHelper()
    private let tokenKey = "asterion.session.token"
    private let userIdKey = "asterion.user.id"

    var isSignedIn: Bool {
        currentUser != nil
    }

    func restoreSession() async {
        sessionToken = keychain.read(key: tokenKey)
    }

    func signOut() {
        Task {
            try? await Clerk.shared.auth.signOut()
        }
        currentUser = nil
        sessionToken = nil
        keychain.delete(key: tokenKey)
        keychain.delete(key: userIdKey)
    }

    func persistSession(token: String, user: User) {
        sessionToken = token
        currentUser = user
        keychain.save(key: tokenKey, value: token)
        keychain.save(key: userIdKey, value: user.id)
    }

    func syncClerkSession() async {
        let clerk = Clerk.shared
        guard let clerkUser = clerk.user else { return }

        do {
            let token = try await clerk.auth.getToken()

            let email = clerkUser.emailAddresses.first?.emailAddress
            let name = [clerkUser.firstName, clerkUser.lastName]
                .compactMap { $0 }
                .joined(separator: " ")
            let displayName = name.isEmpty ? nil : name

            currentUser = User(
                id: clerkUser.id,
                appleUserId: nil,
                email: email,
                username: displayName ?? email,
                pfpUrl: clerkUser.imageUrl,
                bookmarks: []
            )

            sessionToken = token
            keychain.save(key: userIdKey, value: clerkUser.id)
            if let token {
                keychain.save(key: tokenKey, value: token)
            } else {
                keychain.delete(key: tokenKey)
            }
            authError = nil
        } catch {
            authError = error.localizedDescription
        }
    }
}
