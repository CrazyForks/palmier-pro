import Testing
@testable import PalmierPro

@Suite("apply_mask")
@MainActor
struct MaskToolTests {
    private func harness() -> ToolHarness {
        var clip = Fixtures.clip(id: "v1", start: 0, duration: 30)
        clip.mask = Fixtures.mask(mediaRef: clip.mediaRef)
        return ToolHarness(timeline: Fixtures.timeline(tracks: [Fixtures.videoTrack(clips: [clip])]))
    }

    @Test func updatesLiveMaskControls() async {
        let h = harness()
        let result = await h.runRaw("apply_mask", args: [
            "clipId": "v1",
            "action": "update",
            "applied": false,
            "inverted": true,
            "feather": 12.0,
            "expansion": -3.0,
        ])

        #expect(!result.isError)
        let mask = h.editor.clipFor(id: "v1")?.mask
        #expect(mask?.isApplied == false && mask?.inverted == true && mask?.feather == 12 && mask?.expansion == -3)
    }

    @Test func removesMask() async {
        let h = harness()
        _ = await h.runRaw("apply_mask", args: ["clipId": "v1", "action": "remove"])

        #expect(h.editor.clipFor(id: "v1")?.mask == nil)
    }

    @Test func rejectsOutOfRangeControls() async {
        let h = harness()
        let result = await h.runRaw("apply_mask", args: [
            "clipId": "v1",
            "action": "update",
            "feather": 101.0,
        ])

        #expect(result.isError)
    }
}
