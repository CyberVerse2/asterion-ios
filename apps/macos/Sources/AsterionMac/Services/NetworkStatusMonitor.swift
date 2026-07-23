import Foundation
import Network

final class NetworkStatusMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "cloud.cyberverse.asterion.network-status")

    func updates() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { [monitor] _ in
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }

    func cancel() {
        monitor.cancel()
    }
}
