import Foundation
import Testing
@testable import PalmierPro

@Suite("AudioPreviewContent")
struct AudioPreviewContentTests {

    @Test func prefersTranscriptOverLyricsAndPrompt() {
        var input = GenerationInput(
            prompt: "prompt text",
            model: "model",
            duration: 4,
            aspectRatio: "1:1"
        )
        input.lyrics = "lyrics text"

        let block = AudioPreviewContent.text(
            transcript: "  spoken words  ",
            generationInput: input
        )

        #expect(block?.text == "spoken words")
    }

    @Test func prefersLyricsOverPromptWhenNoTranscript() {
        var input = GenerationInput(
            prompt: "prompt text",
            model: "model",
            duration: 4,
            aspectRatio: "1:1"
        )
        input.lyrics = "verse one"

        let block = AudioPreviewContent.text(
            transcript: "   ",
            generationInput: input
        )

        #expect(block?.text == "verse one")
    }

    @Test func fallsBackToPrompt() {
        let input = GenerationInput(
            prompt: "say hello",
            model: "tts",
            duration: 2,
            aspectRatio: "1:1"
        )

        let block = AudioPreviewContent.text(
            transcript: nil,
            generationInput: input
        )

        #expect(block?.text == "say hello")
    }

    @Test func returnsNilWhenNoCopyAvailable() {
        let input = GenerationInput(
            prompt: "   ",
            model: "model",
            duration: 1,
            aspectRatio: "1:1"
        )

        #expect(AudioPreviewContent.text(transcript: nil, generationInput: input) == nil)
        #expect(AudioPreviewContent.text(transcript: nil, generationInput: nil) == nil)
    }

    @Test func showsNotChargedForFailedGenerationWithoutResults() {
        #expect(
            AudioPreviewContent.showsNotChargedNotice(
                isFailed: true,
                hasGenerationInput: true,
                pendingDownloadURL: nil,
                resultURLs: nil
            )
        )
    }

    @Test func hidesNotChargedForDownloadRetryFailures() {
        #expect(
            !AudioPreviewContent.showsNotChargedNotice(
                isFailed: true,
                hasGenerationInput: true,
                pendingDownloadURL: URL(string: "https://example.com/out.mp3"),
                resultURLs: ["https://example.com/out.mp3"]
            )
        )
    }

    @Test func hidesNotChargedWhenResultURLsExist() {
        #expect(
            !AudioPreviewContent.showsNotChargedNotice(
                isFailed: true,
                hasGenerationInput: true,
                pendingDownloadURL: nil,
                resultURLs: ["https://example.com/out.mp3"]
            )
        )
    }

    @Test func hidesNotChargedWithoutGenerationInput() {
        #expect(
            !AudioPreviewContent.showsNotChargedNotice(
                isFailed: true,
                hasGenerationInput: false,
                pendingDownloadURL: nil,
                resultURLs: nil
            )
        )
    }
}
