import os
import Testing
@testable import PalmierPro

@Suite("Scrub audio reader loop")
struct ScrubAudioReaderLoopTests {
    @Test func cancellationWaitsForActiveReadBeforeTeardown() async {
        let reader = ControlledScrubReader()
        let processCount = OSAllocatedUnfairLock(initialState: 0)
        let task = Task {
            try? await ScrubAudioReaderLoop.run(
                next: { await reader.next() },
                process: { _ in processCount.withLock { $0 += 1 } },
                teardown: { await reader.teardown() }
            )
        }

        await reader.waitUntilReadStarts()
        task.cancel()

        #expect(await reader.teardownCallCount() == 0)
        await reader.finishRead(with: 1)
        await task.value
        #expect(processCount.withLock { $0 } == 0)
        #expect(await reader.teardownCallCount() == 1)
    }
}

private actor ControlledScrubReader {
    private var readStarted = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var readContinuation: CheckedContinuation<Int?, Never>?
    private var teardownCalls = 0

    func next() async -> Int? {
        readStarted = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            readContinuation = continuation
        }
    }

    func waitUntilReadStarts() async {
        guard !readStarted else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func finishRead(with value: Int?) {
        readContinuation?.resume(returning: value)
        readContinuation = nil
    }

    func teardown() {
        teardownCalls += 1
    }

    func teardownCallCount() -> Int {
        teardownCalls
    }
}
