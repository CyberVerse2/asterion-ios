enum AccountSessionPresentation: Equatable, Sendable {
    case restoring
    case signedIn
    case signedOut
    case restoreFailed

    static func resolve(
        isSignedIn: Bool,
        isRestoring: Bool,
        expectsPersistedSession: Bool
    ) -> AccountSessionPresentation {
        if isSignedIn {
            return .signedIn
        }
        if isRestoring {
            return .restoring
        }
        if expectsPersistedSession {
            return .restoreFailed
        }
        return .signedOut
    }
}
