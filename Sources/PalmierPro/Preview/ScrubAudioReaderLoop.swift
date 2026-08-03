struct ScrubAudioReaderLoop {
    nonisolated static func run<Payload>(
        next: () async throws -> Payload?,
        process: (Payload) throws -> Void,
        teardown: () async -> Void
    ) async throws {
        let result: Result<Void, Error>
        do {
            while !Task.isCancelled, let payload = try await next() {
                guard !Task.isCancelled else { break }
                try process(payload)
            }
            result = .success(())
        } catch {
            result = .failure(error)
        }

        await teardown()
        try result.get()
    }
}
