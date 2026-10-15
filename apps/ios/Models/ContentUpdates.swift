import Foundation

nonisolated struct ContentWatchTarget: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case novel, anime }
    let kind: Kind
    let contentID: String
    let title: String
    var id: String { "\(kind.rawValue)-\(contentID)" }
}

nonisolated enum ContentUpdatePolicy {
    static func newCount(current: Int, previous: Int?) -> Int? {
        guard let previous, current > previous, previous >= 0 else { return nil }
        return current - previous
    }

    static func nextBaseline(current: Int, previous: Int?) -> Int {
        max(0, current, previous ?? 0)
    }
}

extension Notification.Name {
    static let asterionSavedNovelsChanged = Notification.Name("asterion.savedNovelsChanged")
}
