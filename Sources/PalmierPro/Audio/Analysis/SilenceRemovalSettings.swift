struct SilenceRemovalSettings: Equatable, Sendable {
    static let minimumPauseRange = 0.25...3.0
    static let speechPaddingRange = 0.0...0.5

    static let `default` = SilenceRemovalSettings(
        uncheckedMinimumPauseSeconds: 0.5,
        uncheckedSpeechPaddingSeconds: 0.15
    )

    let minimumPauseSeconds: Double
    let speechPaddingSeconds: Double

    init?(minimumPauseSeconds: Double, speechPaddingSeconds: Double) {
        guard minimumPauseSeconds.isFinite,
              speechPaddingSeconds.isFinite,
              Self.minimumPauseRange.contains(minimumPauseSeconds),
              Self.speechPaddingRange.contains(speechPaddingSeconds) else { return nil }
        self.init(
            uncheckedMinimumPauseSeconds: minimumPauseSeconds,
            uncheckedSpeechPaddingSeconds: speechPaddingSeconds
        )
    }

    private init(uncheckedMinimumPauseSeconds: Double, uncheckedSpeechPaddingSeconds: Double) {
        self.minimumPauseSeconds = uncheckedMinimumPauseSeconds
        self.speechPaddingSeconds = uncheckedSpeechPaddingSeconds
    }
}

enum SilenceRemovalPlanner {
    static func removableMask(
        from quietNonSpeechMask: [Bool],
        settings: SilenceRemovalSettings,
        cellDuration: Double = VoiceActivity.chunkDuration
    ) -> [Bool] {
        guard !quietNonSpeechMask.isEmpty, cellDuration.isFinite, cellDuration > 0 else { return [] }
        let maximumMinimumCells = quietNonSpeechMask.count == Int.max
            ? Int.max
            : quietNonSpeechMask.count + 1
        let minimumCells = cellCount(
            for: settings.minimumPauseSeconds,
            cellDuration: cellDuration,
            maximum: maximumMinimumCells
        )
        let paddingCells = cellCount(
            for: settings.speechPaddingSeconds,
            cellDuration: cellDuration,
            maximum: quietNonSpeechMask.count
        )
        var removable = [Bool](repeating: false, count: quietNonSpeechMask.count)
        var i = 0

        while i < quietNonSpeechMask.count {
            guard quietNonSpeechMask[i] else {
                i += 1
                continue
            }
            var j = i + 1
            while j < quietNonSpeechMask.count, quietNonSpeechMask[j] { j += 1 }
            if j - i >= minimumCells {
                let start = i + (i > 0 ? paddingCells : 0)
                let end = j - (j < quietNonSpeechMask.count ? paddingCells : 0)
                if start < end {
                    for cell in start..<end { removable[cell] = true }
                }
            }
            i = j
        }
        return removable
    }

    private static func cellCount(for seconds: Double, cellDuration: Double, maximum: Int) -> Int {
        let count = (seconds / cellDuration).rounded(.up)
        guard count.isFinite, count < Double(maximum) else { return maximum }
        return max(0, Int(count))
    }
}
