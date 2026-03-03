import ClerkKit
import Combine
import Foundation
import OSLog

@MainActor
final class AuthService: NSObject, ObservableObject {
    @Published var currentUser: User?
    @Published var sessionToken: String?
    @Published var authError: String?

    private let keychain = KeychainHelper()
    private let tokenKey = "asterion.session.token"
    private let userIdKey = "asterion.user.id"
    private let logger = Logger(subsystem: "Asterion", category: "Auth")

    private func debugPrint(_ message: String) {
        #if DEBUG
        print("[AuthService] \(message)")
        #endif
    }

    var isSignedIn: Bool {
        currentUser != nil
    }

    func restoreSession() async {
        sessionToken = keychain.read(key: tokenKey)
        debugPrint("Restore session completed. tokenPresent=\(sessionToken != nil)")
    }

    func signOut() {
        logger.info("Sign out requested.")
        debugPrint("Sign out requested.")
        Task {
            try? await Clerk.shared.auth.signOut()
        }
        currentUser = nil
        sessionToken = nil
        keychain.delete(key: tokenKey)
        keychain.delete(key: userIdKey)
    }

    func persistSession(token: String, user: User) {
        logger.info("Persisting session for userId: \(user.id, privacy: .public)")
        debugPrint("Persisting session for userId: \(user.id)")
        sessionToken = token
        currentUser = user
        keychain.save(key: tokenKey, value: token)
        keychain.save(key: userIdKey, value: user.id)
    }

    func syncClerkSession() async {
        let clerk = Clerk.shared
        guard let clerkUser = clerk.user else {
            logger.info("No Clerk user found during session sync.")
            debugPrint("No Clerk user found during session sync.")
            return
        }
        logger.info("Starting Clerk session sync for userId: \(clerkUser.id, privacy: .public)")
        debugPrint("Starting Clerk session sync for userId: \(clerkUser.id)")

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
            logger.info(
                "Sign in sync succeeded for userId: \(clerkUser.id, privacy: .public), email: \(email ?? "unknown", privacy: .public)"
            )
            debugPrint("Sign in sync succeeded for userId: \(clerkUser.id), email: \(email ?? "unknown")")
        } catch {
            authError = error.localizedDescription
            logger.error("Sign in sync failed: \(error.localizedDescription, privacy: .public)")
            debugPrint("Sign in sync failed: \(error.localizedDescription)")
        }
    }

    func syncUserProfileToBackend(using apiClient: APIClient) async {
        guard let user = currentUser else {
            debugPrint("Profile sync skipped: no signed-in user.")
            return
        }
        debugPrint("Starting backend profile sync for userId: \(user.id)")
        do {
            _ = try await apiClient.updateMyProfile(
                email: user.email,
                username: user.username,
                avatarUrl: user.pfpUrl
            )
            debugPrint("Backend profile sync succeeded for userId: \(user.id)")
        } catch {
            authError = "Signed in, but failed to sync profile to backend."
            debugPrint("Backend profile sync failed for userId: \(user.id): \(error.localizedDescription)")
        }
    }
}
