import CoreGraphics
import Testing
@testable import PalmierPro

@Suite("Viewer mask point mapping")
@MainActor
struct MaskPointMappingTests {
    @Test(arguments: [
        (CGPoint(x: 480, y: 810), Transform(), MaskNormalizedPoint(x: 0.25, y: 0.75)),
        (CGPoint(x: 528, y: 540), Transform(width: 0.5, height: 0.5, flipHorizontal: true), MaskNormalizedPoint(x: 0.95, y: 0.5)),
        (CGPoint(x: 1230, y: 540), Transform(width: 0.5, height: 0.5, rotation: 90), MaskNormalizedPoint(x: 0.5, y: 0)),
    ]) func mapsViewerPoint(point: CGPoint, transform: Transform, expected: MaskNormalizedPoint) throws {
        let mapped = try #require(map(point, transform: transform))
        #expect(abs(mapped.x - expected.x) < 0.0001)
        #expect(abs(mapped.y - expected.y) < 0.0001)
    }

    @Test func rejectsCroppedRegion() {
        #expect(map(CGPoint(x: 192, y: 540), crop: Crop(left: 0.2)) == nil)
    }

    private func map(_ point: CGPoint, transform: Transform = Transform(), crop: Crop = Crop()) -> MaskNormalizedPoint? {
        var clip = Fixtures.clip(id: "clip", start: 0, duration: 30)
        clip.transform = transform
        clip.crop = crop
        return PreviewHitTester.sourceNormalizedPoint(
            at: point,
            viewSize: CGSize(width: 1920, height: 1080),
            clip: clip,
            frame: 0,
            timeline: Fixtures.timeline()
        )
    }
}
