import Foundation

public struct ContentWatchTarget: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case novel, anime }
    public let kind: Kind
    public let contentID: String
    public let title: String
    public var id: String { "\(kind.rawValue)-\(contentID)" }

    public init(kind: Kind, contentID: String, title: String) {
        self.kind = kind
        self.contentID = contentID
        self.title = title
    }
}

public enum ContentUpdatePolicy {
    public static func newCount(current: Int, previous: Int?) -> Int? {
        guard let previous, current > previous, previous >= 0 else { return nil }
        return current - previous
    }

    public static func nextBaseline(current: Int, previous: Int?) -> Int {
        max(0, current, previous ?? 0)
    }
}

extension Notification.Name {
    public static let asterionSavedNovelsChanged = Notification.Name("asterion.savedNovelsChanged")
}
