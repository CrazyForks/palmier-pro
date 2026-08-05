import Foundation

enum AudioPreviewContent {
    struct TextBlock: Equatable, Sendable {
        let text: String
    }

    /// Prefer a cached transcript, then lyrics, then the generation prompt.
    static func text(
        transcript: String?,
        generationInput: GenerationInput?
    ) -> TextBlock? {
        if let transcript = cleaned(transcript) {
            return TextBlock(text: transcript)
        }
        if let lyrics = cleaned(generationInput?.lyrics) {
            return TextBlock(text: lyrics)
        }
        if let prompt = cleaned(generationInput?.prompt) {
            return TextBlock(text: prompt)
        }
        return nil
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
}
