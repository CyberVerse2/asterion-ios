import Foundation

enum ConcurrentBatch {
    static func run<Item: Sendable, Output: Sendable>(
        _ items: [Item],
        maximumConcurrentTasks: Int,
        operation: @escaping @Sendable (Item) async -> Output
    ) async -> [Output] {
        guard !items.isEmpty else { return [] }

        let limit = max(1, min(maximumConcurrentTasks, items.count))

        return await withTaskGroup(of: (Int, Output).self) { group in
            for index in 0..<limit {
                let item = items[index]
                group.addTask {
                    (index, await operation(item))
                }
            }

            var nextIndex = limit
            var outputs: [(Int, Output)] = []
            outputs.reserveCapacity(items.count)
            while let output = await group.next() {
                outputs.append(output)
                if nextIndex < items.count {
                    let index = nextIndex
                    let item = items[index]
                    nextIndex += 1
                    group.addTask {
                        (index, await operation(item))
                    }
                }
            }

            return outputs.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
