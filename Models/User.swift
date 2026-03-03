import Foundation

struct User: Identifiable, Codable, Hashable {
    let id: String
    let appleUserId: String?
    let email: String?
    let username: String?
    let pfpUrl: String?
    let bookmarks: [String]
}
