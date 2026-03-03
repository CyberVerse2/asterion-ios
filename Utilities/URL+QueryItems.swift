import Foundation

extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        var currentItems = components.queryItems ?? []
        currentItems.append(contentsOf: queryItems)
        components.queryItems = currentItems
        return components.url ?? self
    }
}
