import Testing
@testable import AsterionMac

struct AccountSessionPresentationTests {
    @Test func signedInWinsOverRestoringAndAPreviousSession() {
        #expect(
            AccountSessionPresentation.resolve(
                isSignedIn: true,
                isRestoring: true,
                expectsPersistedSession: true
            ) == .signedIn
        )
    }

    @Test func restoringHidesTheSignedOutMarketingState() {
        #expect(
            AccountSessionPresentation.resolve(
                isSignedIn: false,
                isRestoring: true,
                expectsPersistedSession: false
            ) == .restoring
        )
        #expect(
            AccountSessionPresentation.resolve(
                isSignedIn: false,
                isRestoring: true,
                expectsPersistedSession: true
            ) == .restoring
        )
    }

    @Test func aPreviousSessionSurfacesRestoreFailedInsteadOfSignedOut() {
        #expect(
            AccountSessionPresentation.resolve(
                isSignedIn: false,
                isRestoring: false,
                expectsPersistedSession: true
            ) == .restoreFailed
        )
    }

    @Test func aFreshInstallShowsSignedOut() {
        #expect(
            AccountSessionPresentation.resolve(
                isSignedIn: false,
                isRestoring: false,
                expectsPersistedSession: false
            ) == .signedOut
        )
    }
}
