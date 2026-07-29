import AVFoundation
import CoreImage
import Testing
@testable import PalmierPro

@Suite("Apple mask generator", .serialized)
struct AppleMaskGeneratorTests {
    @Test func temporalRefinementRemovesSingleFrameOutlier() throws {
        let size = CGSize(width: 8, height: 8)
        var refiner = MaskTemporalRefiner(emitsFirstSample: true)

        _ = refiner.append(solidMask(0, size: size), at: .zero)
        _ = refiner.append(solidMask(1, size: size), at: CMTime(value: 1, timescale: 30))
        let refined = refiner.append(
            solidMask(0, size: size),
            at: CMTime(value: 2, timescale: 30)
        )
        let output = try #require(refined)

        #expect(maskValue(output.image, x: 4, y: 4) < 0.05)
    }

    @Test func temporalRefinementPreservesMovingEdge() throws {
        let size = CGSize(width: 12, height: 8)
        var refiner = MaskTemporalRefiner(emitsFirstSample: false)

        _ = refiner.append(leftMask(size: size, width: 3), at: .zero)
        _ = refiner.append(leftMask(size: size, width: 6), at: CMTime(value: 1, timescale: 30))
        let refined = refiner.append(
            leftMask(size: size, width: 9),
            at: CMTime(value: 2, timescale: 30)
        )
        let output = try #require(refined)

        #expect(maskValue(output.image, x: 4, y: 4) > 0.95)
        #expect(maskValue(output.image, x: 7, y: 4) < 0.05)
    }

    @Test func temporalRefinementHardensSoftAlpha() throws {
        var refiner = MaskTemporalRefiner(emitsFirstSample: true)
        let refined = refiner.append(
            solidMask(0.4, size: CGSize(width: 8, height: 8)),
            at: .zero
        )
        let output = try #require(refined)

        #expect(maskValue(output.image, x: 4, y: 4) < 0.3)
    }

    @Test func writesForwardSourceRange() async throws {
        let sourceURL = try await CompositorFixtures.patternVideoURL()
        let destination = temporaryMaskURL()
        defer { try? FileManager.default.removeItem(at: destination) }
        let range = MediaTimeRange(CMTimeRange(
            start: CMTime(value: 10, timescale: 30),
            duration: CMTime(value: 15, timescale: 30)
        ))

        let output = try await generate(
            sourceURL: sourceURL,
            range: range,
            destination: destination,
            segmenter: { image, _ in leftMask(size: image.extent.size) }
        )

        let asset = AVURLAsset(url: destination)
        let track = try #require(await asset.loadTracks(withMediaType: .video).first)
        let description = try #require(await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_HEVC)
        #expect(abs(try await asset.load(.duration).seconds - 0.5) < 0.04)
        #expect(output == range)

        let image = CIImage(cgImage: try await frame(in: asset, at: .zero))
        #expect(maskValue(image, x: image.extent.width / 4, y: image.extent.height / 2) > 0.9)
        #expect(maskValue(image, x: image.extent.width * 3 / 4, y: image.extent.height / 2) < 0.1)
    }

    @Test func generatesLeadInBackwardFromSelection() async throws {
        let sourceURL = try await FixtureVideo.write(
            scenes: [
                .init(rgb: (0, 0, 0), seconds: 0.5),
                .init(rgb: (255, 255, 255), seconds: 0.5),
            ],
            fps: 10,
            size: 64
        )
        let destination = temporaryMaskURL()
        defer { remove([sourceURL, destination]) }
        let inputs = SegmenterInputs()
        let range = MediaTimeRange(CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 1, preferredTimescale: 600)
        ))

        let output = try await generate(
            sourceURL: sourceURL,
            range: range,
            selectionTime: CMTime(seconds: 0.5, preferredTimescale: 600),
            destination: destination,
            segmenter: { image, _ in
                let bright = frameIsBright(image)
                await inputs.record(bright)
                return leftMask(size: image.extent.size, whiteOnLeft: !bright)
            }
        )

        #expect(await inputs.first == true)
        #expect(output.start == range.start)
        #expect(abs(output.duration.cmTime.seconds - 1) < 0.001)
        let asset = AVURLAsset(url: destination)
        let early = CIImage(cgImage: try await frame(in: asset, at: CMTime(seconds: 0.1, preferredTimescale: 600)))
        let late = CIImage(cgImage: try await frame(in: asset, at: CMTime(seconds: 0.7, preferredTimescale: 600)))
        #expect(maskValue(early, x: 16, y: 32) > 0.9 && maskValue(early, x: 48, y: 32) < 0.1)
        #expect(maskValue(late, x: 16, y: 32) < 0.1 && maskValue(late, x: 48, y: 32) > 0.9)
    }

    @Test func briefSegmentationLossHoldsPreviousMask() async throws {
        try await assertSegmentationLoss(failures: 4, succeeds: true)
    }

    @Test func prolongedSegmentationLossFailsAndRemovesArtifact() async throws {
        try await assertSegmentationLoss(failures: 5, succeeds: false)
    }

    @Test func cancellationRemovesPartialArtifact() async throws {
        let sourceURL = try await CompositorFixtures.patternVideoURL()
        let destination = temporaryMaskURL()
        defer { try? FileManager.default.removeItem(at: destination) }
        let range = MediaTimeRange(CMTimeRange(
            start: .zero,
            duration: CMTime(value: 15, timescale: 30)
        ))
        let entered = AsyncStream.makeStream(of: Void.self)
        let release = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            try await generate(
                sourceURL: sourceURL,
                range: range,
                destination: destination,
                segmenter: { image, _ in
                    entered.continuation.yield()
                    for await _ in release.stream.prefix(1) {}
                    try Task.checkCancellation()
                    return leftMask(size: image.extent.size)
                }
            )
        }
        _ = await entered.stream.first { _ in true }
        task.cancel()
        release.continuation.yield()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

private func generate(
    sourceURL: URL,
    range: MediaTimeRange,
    selectionTime: CMTime? = nil,
    destination: URL,
    segmenter: @escaping AppleMaskGenerator.Segmenter
) async throws -> MediaTimeRange {
    try await AppleMaskGenerator.generate(
        sourceURL: sourceURL,
        sourceRange: range,
        selection: MaskSelection(
            point: MaskNormalizedPoint(x: 0.25, y: 0.5),
            sourceTime: MediaTime(selectionTime ?? range.start.cmTime)
        ),
        destinationURL: destination,
        segmenter: segmenter
    )
}

private func assertSegmentationLoss(failures: Int, succeeds: Bool) async throws {
    let sourceURL = try await FixtureVideo.write(
        scenes: [.init(rgb: (255, 255, 255), seconds: 1)],
        fps: 10,
        size: 64
    )
    let destination = temporaryMaskURL()
    defer { remove([sourceURL, destination]) }
    let sequence = FailureSequence(count: failures)
    let range = MediaTimeRange(CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)))
    let operation = {
        try await generate(
            sourceURL: sourceURL,
            range: range,
            destination: destination,
            segmenter: { image, _ in
                if await sequence.shouldFail() { throw AppleMaskGenerator.GenerationError.noSubject }
                return leftMask(size: image.extent.size)
            }
        )
    }

    if succeeds {
        let output = try await operation()
        #expect(output.start == range.start)
        #expect(abs(output.duration.cmTime.seconds - range.duration.cmTime.seconds) < 0.001)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    } else {
        await #expect(throws: AppleMaskGenerator.GenerationError.noSubject) { try await operation() }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

private actor FailureSequence {
    let count: Int
    var calls = 0

    init(count: Int) { self.count = count }

    func shouldFail() -> Bool {
        defer { calls += 1 }
        return calls > 0 && calls <= count
    }
}

private actor SegmenterInputs {
    var values: [Bool] = []
    var first: Bool? { values.first }
    func record(_ value: Bool) { values.append(value) }
}

private func solidMask(_ value: CGFloat, size: CGSize) -> CIImage {
    CIImage(color: CIColor(red: value, green: value, blue: value))
        .cropped(to: CGRect(origin: .zero, size: size))
}

private func leftMask(size: CGSize, width: CGFloat? = nil, whiteOnLeft: Bool = true) -> CIImage {
    let full = CGRect(origin: .zero, size: size)
    let width = width ?? size.width / 2
    let x = whiteOnLeft ? 0 : size.width - width
    return solidMask(1, size: CGSize(width: width, height: size.height))
        .transformed(by: CGAffineTransform(translationX: x, y: 0))
        .composited(over: solidMask(0, size: size))
        .cropped(to: full)
}

private func maskValue(_ image: CIImage, x: CGFloat, y: CGFloat) -> Float {
    var value: Float = 0
    CIContext().render(image, toBitmap: &value, rowBytes: MemoryLayout<Float>.size,
                       bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .Rf, colorSpace: nil)
    return value
}

private func frameIsBright(_ image: CIImage) -> Bool {
    let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
    return maskValue(average, x: 0, y: 0) > 0.5
}

private func frame(in asset: AVAsset, at time: CMTime) async throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try await generator.image(at: time).image
}

private func temporaryMaskURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mask-\(UUID().uuidString).mov")
}

private func remove(_ urls: [URL]) {
    for url in urls { try? FileManager.default.removeItem(at: url) }
}
