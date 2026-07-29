import AVFoundation
import CoreImage

struct MaskTemporalRefiner {
    struct Sample {
        let image: CIImage
        let time: CMTime
    }

    private static let kernel = CIKernelLoader.kernel("MaskRefinement", "maskTemporalMedian")
    private static let lowerEdge: Float = 0.3
    private static let upperEdge: Float = 0.7

    private let emitsFirstSample: Bool
    private var pending: [Sample] = []

    init(emitsFirstSample: Bool) {
        self.emitsFirstSample = emitsFirstSample
    }

    mutating func append(_ image: CIImage, at time: CMTime) -> Sample? {
        let sample = Sample(image: image, time: time)
        pending.append(sample)
        if pending.count == 1, emitsFirstSample {
            return Sample(image: Self.refine(image, image, image), time: time)
        }
        guard pending.count == 3 else { return nil }
        let output = Sample(
            image: Self.refine(pending[0].image, pending[1].image, pending[2].image),
            time: pending[1].time
        )
        pending.removeFirst()
        return output
    }

    mutating func finish() -> Sample? {
        defer { pending.removeAll() }
        guard pending.count >= 2, let last = pending.last else { return nil }
        return Sample(image: Self.refine(last.image, last.image, last.image), time: last.time)
    }

    private static func refine(_ previous: CIImage, _ current: CIImage, _ next: CIImage) -> CIImage {
        kernel?.apply(
            extent: current.extent,
            roiCallback: { _, rect in rect },
            arguments: [previous, current, next, lowerEdge, upperEdge]
        ) ?? current
    }
}
