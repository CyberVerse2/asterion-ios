import Combine
import Foundation

@MainActor
final class FootballPlayerStore: ObservableObject {
    @Published private(set) var streams: [FootballStream] = []
    @Published private(set) var selectedStreamID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let api: FootballAPI
    private var route: FootballPlayerRoute?
    private var requestID = UUID()

    init(api: FootballAPI = FootballAPI()) {
        self.api = api
    }

    var selectedStream: FootballStream? {
        streams.first { $0.optionID == selectedStreamID }
    }

    func load(route: FootballPlayerRoute, force: Bool = false) async {
        guard force || self.route != route || streams.isEmpty else { return }

        self.route = route
        let currentRequestID = UUID()
        requestID = currentRequestID
        isLoading = true
        error = nil
        streams = []
        selectedStreamID = nil

        do {
            let fetched = try await api.fetchStreams(for: route.match)
            guard !Task.isCancelled, requestID == currentRequestID else { return }
            streams = fetched.sorted(by: Self.preferredOrder)
            selectedStreamID = streams.first?.optionID
            isLoading = false
        } catch {
            guard !Task.isCancelled, requestID == currentRequestID else { return }
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func retry() async {
        guard let route else { return }
        await load(route: route, force: true)
    }

    func choose(_ stream: FootballStream) {
        guard streams.contains(stream) else { return }
        selectedStreamID = stream.optionID
    }

    private static func preferredOrder(_ left: FootballStream, _ right: FootballStream) -> Bool {
        if left.hd != right.hd { return left.hd }
        let leftIsEnglish = left.language.localizedCaseInsensitiveCompare("English") == .orderedSame
        let rightIsEnglish = right.language.localizedCaseInsensitiveCompare("English") == .orderedSame
        if leftIsEnglish != rightIsEnglish { return leftIsEnglish }
        return (left.viewers ?? 0) > (right.viewers ?? 0)
    }
}
