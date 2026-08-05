import Foundation

enum AudioPreviewContent {
    struct TextBlock: Equatable, Sendable {
        let lines: [String]

        var isEmpty: Bool { lines.isEmpty }
    }

    struct TimedLine: Equatable, Sendable {
        let text: String
        let start: Double
        let end: Double
    }

    /// Prefer a cached transcript, then lyrics, then the generation prompt.
    static func text(
        transcript: String?,
        generationInput: GenerationInput?
    ) -> TextBlock? {
        if let transcript = cleaned(transcript) {
            return TextBlock(lines: lines(from: transcript))
        }
        if let lyrics = cleaned(generationInput?.lyrics) {
            return TextBlock(lines: lines(from: lyrics))
        }
        if let prompt = cleaned(generationInput?.prompt) {
            return TextBlock(lines: lines(from: prompt))
        }
        return nil
    }

    static func timedLines(from transcript: TranscriptionResult?) -> [TimedLine] {
        guard let transcript else { return [] }
        let segments = transcript.segments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !segments.isEmpty {
            return segments.map {
                TimedLine(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: $0.start,
                    end: max($0.end, $0.start)
                )
            }
        }
        return lines(from: transcript.text).map {
            TimedLine(text: $0, start: 0, end: 0)
        }
    }

    static func lines(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains(where: \.isNewline) {
            return trimmed
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return splitIntoPhrases(trimmed)
    }

    static func activeLineIndex(progress: Double, lineCount: Int) -> Int {
        guard lineCount > 0 else { return 0 }
        guard lineCount > 1 else { return 0 }
        let clamped = min(1, max(0, progress))
        return min(lineCount - 1, Int(clamped * Double(lineCount)))
    }

    static func activeTimedLineIndex(time: Double, lines: [TimedLine]) -> Int {
        guard !lines.isEmpty else { return 0 }
        if let exact = lines.firstIndex(where: { time >= $0.start && time < $0.end }) {
            return exact
        }
        if let lastStarted = lines.lastIndex(where: { time >= $0.start }) {
            return lastStarted
        }
        return 0
    }

    /// Failed generations are refunded; download failures after a successful job were charged.
    static func showsNotChargedNotice(
        isFailed: Bool,
        hasGenerationInput: Bool,
        pendingDownloadURL: URL?,
        resultURLs: [String]?
    ) -> Bool {
        guard isFailed else { return false }
        guard hasGenerationInput else { return false }
        guard pendingDownloadURL == nil else { return false }
        if let resultURLs, !resultURLs.isEmpty { return false }
        return true
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func splitIntoPhrases(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ".!?;")
        var phrases: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character.unicodeScalars.count == 1,
               let scalar = character.unicodeScalars.first,
               separators.contains(scalar) {
                let phrase = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !phrase.isEmpty { phrases.append(phrase) }
                current = ""
            }
        }
        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty { phrases.append(trailing) }
        return phrases.isEmpty ? [text] : phrases
    }
}
