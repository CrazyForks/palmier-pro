import Testing
@testable import PalmierPro
@Test func activeTranscriptLineFollowsSegmentStart() {
    let lines = [
        TranscriptionSegment(text: "One", start: 0, end: 1),
        TranscriptionSegment(text: "Two", start: 1, end: 3),
    ]
    #expect(AudioPreviewView.activeLineIndex(at: 0.5, in: lines) == 0
        && AudioPreviewView.activeLineIndex(at: 2, in: lines) == 1)
}
