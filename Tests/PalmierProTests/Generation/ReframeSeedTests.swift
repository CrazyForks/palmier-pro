import Foundation
import Testing
@testable import PalmierPro

@Suite("Reframe seed")
@MainActor
struct ReframeSeedTests {
    @Test("Seeds MiniMax H3 with video reference and fill prompt")
    func seedsVideoReferenceAndPrompt() throws {
        let model = try Self.minimaxH3()
        let asset = MediaAsset(
            id: "clip-1",
            url: URL(fileURLWithPath: "/tmp/wide.mp4"),
            type: .video,
            name: "Wide",
            duration: 8.2
        )
        asset.sourceWidth = 1920
        asset.sourceHeight = 1080

        let seed = try #require(EditSubmitter.reframeSeed(for: asset, model: model))

        #expect(seed.model == "minimax-h3")
        #expect(seed.prompt == VideoModelConfig.reframePrompt)
        #expect(seed.aspectRatio == "9:16")
        #expect(seed.resolution == "2K")
        #expect(seed.duration == 8)
        #expect(seed.referenceVideoAssetIds == ["clip-1"])
        #expect(seed.imageURLAssetIds == nil)
    }

    @Test("Portrait sources reframe to landscape")
    func flipsPortraitToLandscape() throws {
        let model = try Self.minimaxH3()
        let asset = MediaAsset(
            id: "clip-2",
            url: URL(fileURLWithPath: "/tmp/tall.mp4"),
            type: .video,
            name: "Tall",
            duration: 5
        )
        asset.sourceWidth = 1080
        asset.sourceHeight = 1920

        let seed = try #require(EditSubmitter.reframeSeed(for: asset, model: model))
        #expect(seed.aspectRatio == "16:9")
    }

    @Test("Rejects models that cannot take video references")
    func rejectsSourceOnlyModels() throws {
        let model = try Self.sourceEditModel()
        let asset = MediaAsset(
            id: "clip-3",
            url: URL(fileURLWithPath: "/tmp/clip.mp4"),
            type: .video,
            name: "Clip",
            duration: 5
        )
        #expect(EditSubmitter.reframeSeed(for: asset, model: model) == nil)
        #expect(!VideoModelConfig.isReframeModel(model))
    }

    @Test("Snaps duration to the nearest supported value")
    func snapsDuration() throws {
        let model = try Self.minimaxH3()
        #expect(model.preferredReframeDuration(for: 7.6) == 8)
        #expect(model.preferredReframeDuration(for: 4.1) == 5)
        #expect(model.preferredReframeDuration(for: 20) == 15)
        #expect(model.validateReframeDuration(16) != nil)
        #expect(model.validateReframeDuration(10) == nil)
    }

    private static func minimaxH3() throws -> VideoModelConfig {
        try decodeVideoModel(#"""
        {
          "id": "minimax-h3",
          "kind": "video",
          "displayName": "MiniMax H3",
          "providerIconKey": "minimax",
          "allowedEndpoints": ["opaque"],
          "responseShape": "video",
          "uiCapabilities": {
            "supportsPrompt": true,
            "durations": [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
            "resolutions": ["768P", "2K"],
            "aspectRatios": ["16:9", "9:16", "1:1"],
            "supportsFirstFrame": false,
            "supportsLastFrame": false,
            "maxReferenceImages": 9,
            "maxReferenceVideos": 3,
            "maxReferenceAudios": 3,
            "maxTotalReferences": 12,
            "maxCombinedVideoRefSeconds": 15,
            "maxCombinedAudioRefSeconds": 15,
            "framesAndReferencesExclusive": false,
            "referenceTagNoun": "Video",
            "requiresSourceVideo": false,
            "maxSourceVideoSeconds": null,
            "requiresReferenceImage": false,
            "requiresReferenceAudio": false
          }
        }
        """#)
    }

    private static func sourceEditModel() throws -> VideoModelConfig {
        try decodeVideoModel(#"""
        {
          "id": "kling-reframe",
          "kind": "video",
          "displayName": "Legacy Reframe",
          "allowedEndpoints": ["opaque"],
          "responseShape": "video",
          "uiCapabilities": {
            "supportsPrompt": true,
            "durations": [5, 10],
            "resolutions": ["1080p"],
            "aspectRatios": ["16:9", "9:16"],
            "supportsFirstFrame": false,
            "supportsLastFrame": false,
            "maxReferenceImages": 0,
            "maxReferenceVideos": 0,
            "maxReferenceAudios": 0,
            "maxTotalReferences": null,
            "maxCombinedVideoRefSeconds": null,
            "maxCombinedAudioRefSeconds": null,
            "framesAndReferencesExclusive": false,
            "referenceTagNoun": "Video",
            "requiresSourceVideo": true,
            "maxSourceVideoSeconds": 10,
            "requiresReferenceImage": false,
            "requiresReferenceAudio": false
          }
        }
        """#)
    }

    private static func decodeVideoModel(_ json: String) throws -> VideoModelConfig {
        let entry = try JSONDecoder().decode(CatalogEntry.self, from: Data(json.utf8))
        guard case .video(let caps) = entry.uiCapabilities else {
            Issue.record("Expected video capabilities")
            throw DecodeError.wrongKind
        }
        return VideoModelConfig(entry: entry, caps: caps)
    }

    private enum DecodeError: Error { case wrongKind }
}
