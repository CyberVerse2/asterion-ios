import Testing
@testable import AsterionMac

struct ConcurrentBatchTests {
    @Test func batchRunsConcurrentlyWithinItsLimitAndPreservesOrder() async {
        let probe = ConcurrentBatchProbe()

        let output = await ConcurrentBatch.run(
            Array(0..<12),
            maximumConcurrentTasks: 4
        ) { value in
            await probe.begin()
            try? await Task.sleep(for: .milliseconds(5))
            await probe.end()
            return value * 2
        }
        let maximumActive = await probe.maximumActive

        #expect(output == Array(0..<12).map { $0 * 2 })
        #expect(maximumActive > 1)
        #expect(maximumActive <= 4)
    }
}

private actor ConcurrentBatchProbe {
    private var active = 0
    private(set) var maximumActive = 0

    func begin() {
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func end() {
        active -= 1
    }
}
