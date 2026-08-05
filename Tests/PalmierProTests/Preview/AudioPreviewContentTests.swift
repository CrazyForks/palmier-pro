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

        #expect(block?.lines == ["spoken words"])
    }

    @Test func prefersLyricsOverPromptWhenNoTranscript() {
        var input = GenerationInput(
            prompt: "prompt text",
            model: "model",
            duration: 4,
            aspectRatio: "1:1"
        )
        input.lyrics = "verse one\nverse two"

        let block = AudioPreviewContent.text(
            transcript: "   ",
            generationInput: input
        )

        #expect(block?.lines == ["verse one", "verse two"])
    }

    @Test func fallsBackToPromptPhrases() {
        let input = GenerationInput(
            prompt: "Say hello. Then leave.",
            model: "tts",
            duration: 2,
            aspectRatio: "1:1"
        )

        let block = AudioPreviewContent.text(
            transcript: nil,
            generationInput: input
        )

        #expect(block?.lines == ["Say hello.", "Then leave."])
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

    @Test func activeLineIndexTracksProgress() {
        #expect(AudioPreviewContent.activeLineIndex(progress: 0, lineCount: 4) == 0)
        #expect(AudioPreviewContent.activeLineIndex(progress: 0.5, lineCount: 4) == 2)
        #expect(AudioPreviewContent.activeLineIndex(progress: 0.99, lineCount: 4) == 3)
        #expect(AudioPreviewContent.activeLineIndex(progress: 1, lineCount: 1) == 0)
    }

    @Test func activeTimedLineIndexUsesSegmentBounds() {
        let lines = [
            AudioPreviewContent.TimedLine(text: "one", start: 0, end: 1),
            AudioPreviewContent.TimedLine(text: "two", start: 1, end: 3),
            AudioPreviewContent.TimedLine(text: "three", start: 3, end: 5),
        ]
        #expect(AudioPreviewContent.activeTimedLineIndex(time: 0.2, lines: lines) == 0)
        #expect(AudioPreviewContent.activeTimedLineIndex(time: 1.5, lines: lines) == 1)
        #expect(AudioPreviewContent.activeTimedLineIndex(time: 4.0, lines: lines) == 2)
        #expect(AudioPreviewContent.activeTimedLineIndex(time: 9.0, lines: lines) == 2)
    }

    @Test func timedLinesPreferSegments() {
        let result = TranscriptionResult(
            text: "ignored",
            language: "en",
            words: [],
            segments: [
                TranscriptionSegment(text: " Hello ", start: 0, end: 1),
                TranscriptionSegment(text: "world", start: 1, end: 2),
            ]
        )
        let lines = AudioPreviewContent.timedLines(from: result)
        #expect(lines.map(\.text) == ["Hello", "world"])
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
