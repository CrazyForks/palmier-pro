import Testing
@testable import PalmierPro

@Suite("Custom aspect ratio")
struct CustomAspectRatioTests {
    @Test(arguments: [
        ("3:2", 1080, 1620, 1080),
        ("9:16", 2160, 2160, 3840),
        ("2.39:1", 1080, 2582, 1080),
        ("2.4:1", 1080, 2592, 1080),
    ])
    func preservesShortEdge(
        ratio: String,
        shortEdge: Int,
        expectedWidth: Int,
        expectedHeight: Int
    ) throws {
        let result = try CanvasAspectRatio(ratio).resolution(shortEdge: shortEdge)
        #expect(result.width == expectedWidth)
        #expect(result.height == expectedHeight)
    }

    @Test(arguments: ["", "16", ":9", "16:", "0:1", "1:0", "-1:1", "nan:1", "1:inf"])
    func rejectsInvalidRatios(_ ratio: String) {
        #expect(throws: AspectRatioError.self) {
            try CanvasAspectRatio(ratio)
        }
    }

    @Test func rejectsOversizedResolution() throws {
        let ratio = try CanvasAspectRatio("100:1")
        #expect(throws: AspectRatioError.self) {
            try ratio.resolution(shortEdge: 1080)
        }
    }
}
