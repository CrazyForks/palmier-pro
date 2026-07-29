import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Vision

enum AppleMaskGenerator {
    typealias Segmenter = @Sendable (CIImage, CGPoint) async throws -> CIImage

    enum GenerationError: LocalizedError {
        case noVideoTrack, invalidSourceRange, readerSetupFailed, writerSetupFailed
        case frameConversionFailed, noSubject, noFrames, appendFailed, writeFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: "The source has no video track."
            case .invalidSourceRange: "The requested source range is unavailable."
            case .readerSetupFailed, .noFrames: "Couldn’t read the requested video frames."
            case .writerSetupFailed, .appendFailed, .writeFailed: "Couldn’t write the mask video."
            case .frameConversionFailed: "Couldn’t prepare a frame for analysis."
            case .noSubject: "No foreground object was found at that point."
            }
        }
    }

    @concurrent
    static func generate(
        sourceURL: URL,
        sourceRange requestedRange: MediaTimeRange,
        selection: MaskSelection,
        destinationURL: URL,
        segmenter: Segmenter? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> MediaTimeRange {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GenerationError.noVideoTrack
        }
        let trackRange = try await track.load(.timeRange)
        let preferredTransform = try await track.load(.preferredTransform)
        let naturalSize = try await track.load(.naturalSize)
        let logicalStart = requestedRange.start.cmTime
        let absoluteStart = trackRange.start + logicalStart
        let availableDuration = trackRange.end - absoluteStart
        let duration = CMTimeMinimum(requestedRange.duration.cmTime, availableDuration)
        let absoluteEnd = absoluteStart + duration
        let absoluteSelection = trackRange.start + selection.sourceTime.cmTime
        guard logicalStart >= .zero,
              absoluteStart >= trackRange.start,
              duration > .zero,
              absoluteSelection >= absoluteStart,
              absoluteSelection < absoluteEnd
        else {
            throw GenerationError.invalidSourceRange
        }

        let geometry = SourceGeometry(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )
        let sourceFPS = try await track.load(.nominalFrameRate)
        let nominalFPS = sourceFPS > 0 ? max(1, Int(sourceFPS.rounded())) : 30
        let context = CIContext(options: [.cacheIntermediates: false])
        let selectionPoint = CGPoint(x: selection.point.x, y: selection.point.y)
        let spoolURL = FileIO.temporaryFileURL(pathExtension: "mask-spool")
        let spool = try MaskSpool(url: spoolURL, context: context)
        defer { try? FileManager.default.removeItem(at: spoolURL) }
        var reader: AVAssetReader?
        var writer: MaskWriter?
        var outputFrameCount = 0
        var progress = ProgressReporter(handler: onProgress)

        do {
            var anchorTime = absoluteSelection
            if absoluteSelection > absoluteStart {
                let frameDuration = (try? await track.load(.minFrameDuration)).flatMap {
                    $0.isNumeric && $0 > .zero ? $0 : nil
                } ?? CMTime(value: 1, timescale: CMTimeScale(nominalFPS))
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.requestedTimeToleranceBefore = .zero
                imageGenerator.requestedTimeToleranceAfter = frameDuration
                let anchor = try await imageGenerator.image(at: absoluteSelection)
                anchorTime = min(absoluteEnd, max(absoluteStart, anchor.actualTime))
                let backward = MaskProcessor(
                    context: context,
                    segmenter: segmenter,
                    selectionPoint: selectionPoint,
                    orientation: geometry.orientation
                )
                var refiner = MaskTemporalRefiner(emitsFirstSample: false)
                let anchorMask = try await backward.mask(.cgImage(anchor.image))
                _ = refiner.append(anchorMask, at: anchorTime - absoluteStart)
                let earlierTimes = try sampleTimes(
                    asset: asset,
                    track: track,
                    range: CMTimeRange(start: absoluteStart, end: anchorTime)
                )
                imageGenerator.requestedTimeToleranceAfter = .zero
                for time in earlierTimes.reversed() where time < anchorTime {
                    try Task.checkCancellation()
                    let image = try await imageGenerator.image(at: time).image
                    let mask = try await backward.mask(.cgImage(image))
                    if let refined = refiner.append(mask, at: time - absoluteStart) {
                        try spool.append(geometry.output(refined.image), at: refined.time)
                    }
                    progress.report(min(1, (anchorTime - time).seconds / duration.seconds))
                }
                try Task.checkCancellation()
                if let refined = refiner.finish() {
                    try spool.append(geometry.output(refined.image), at: refined.time)
                }
            }
            try spool.finishWriting()

            let createdWriter = try MaskWriter(
                destinationURL: destinationURL,
                geometry: geometry,
                nominalFPS: nominalFPS,
                context: context
            )
            writer = createdWriter
            try createdWriter.start()
            outputFrameCount += try await spool.replay(into: createdWriter)

            let forwardRange = CMTimeRange(start: anchorTime, end: absoluteEnd)
            let forward = try makeReader(asset: asset, track: track, range: forwardRange)
            reader = forward.reader
            guard forward.reader.startReading() else {
                throw forward.reader.error ?? GenerationError.readerSetupFailed
            }
            let processor = MaskProcessor(
                context: context,
                segmenter: segmenter,
                selectionPoint: selectionPoint,
                orientation: geometry.orientation
            )
            var refiner = MaskTemporalRefiner(emitsFirstSample: true)
            while let sample = forward.output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
                    throw GenerationError.frameConversionFailed
                }
                let mask = try await processor.mask(.pixelBuffer(buffer))
                let sourceTime = CMSampleBufferGetPresentationTimeStamp(sample)
                let sampleTime = CMTimeMaximum(.zero, sourceTime - absoluteStart)
                if let refined = refiner.append(mask, at: sampleTime) {
                    try await createdWriter.append(geometry.output(refined.image), at: refined.time)
                    outputFrameCount += 1
                }
                progress.report(min(1, max(0, sampleTime.seconds / duration.seconds)))
            }

            try Task.checkCancellation()
            if let refined = refiner.finish() {
                try await createdWriter.append(geometry.output(refined.image), at: refined.time)
                outputFrameCount += 1
            }

            guard forward.reader.status != .failed else {
                throw forward.reader.error ?? GenerationError.readerSetupFailed
            }
            guard outputFrameCount > 0 else { throw GenerationError.noFrames }
            try await createdWriter.finish(at: duration)
            onProgress?(1)
        } catch {
            reader?.cancelReading()
            writer?.cancel()
            try? spool.finishWriting()
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        return MediaTimeRange(
            start: requestedRange.start,
            duration: MediaTime(duration)
        )
    }

    private struct ProgressReporter {
        let handler: (@Sendable (Double) -> Void)?
        var last = -1.0

        mutating func report(_ progress: Double) {
            guard let handler, progress - last >= 0.01 else { return }
            last = progress
            handler(progress)
        }
    }

    private static func sampleTimes(
        asset: AVAsset,
        track: AVAssetTrack,
        range: CMTimeRange
    ) throws -> [CMTime] {
        guard range.duration > .zero else { return [] }
        let source = try makeReader(asset: asset, track: track, range: range)
        guard source.reader.startReading() else {
            throw source.reader.error ?? GenerationError.readerSetupFailed
        }
        var times: [CMTime] = []
        while let sample = source.output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            if time < range.end { times.append(time) }
        }
        guard source.reader.status != .failed else {
            throw source.reader.error ?? GenerationError.readerSetupFailed
        }
        return Array(Set(times)).sorted()
    }

    private static func makeReader(
        asset: AVAsset,
        track: AVAssetTrack,
        range: CMTimeRange
    ) throws -> (reader: AVAssetReader, output: AVAssetReaderTrackOutput) {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw GenerationError.readerSetupFailed }
        reader.add(output)
        return (reader, output)
    }

    private final class MaskSpool {
        private struct Entry {
            let time: CMTime
            let offset: UInt64
            let length: Int
        }

        private let url: URL
        private let context: CIContext
        private var handle: FileHandle?
        private var entries: [Entry] = []

        init(url: URL, context: CIContext) throws {
            self.url = url
            self.context = context
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw GenerationError.writerSetupFailed
            }
            do {
                handle = try FileHandle(forWritingTo: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }

        func append(_ mask: CIImage, at time: CMTime) throws {
            guard let handle,
                  let data = context.pngRepresentation(
                    of: mask,
                    format: .L8,
                    colorSpace: CGColorSpaceCreateDeviceGray(),
                    options: [:]
                  )
            else { throw GenerationError.frameConversionFailed }
            let offset = try handle.offset()
            try handle.write(contentsOf: data)
            entries.append(Entry(time: time, offset: offset, length: data.count))
        }

        func finishWriting() throws {
            guard let handle else { return }
            try handle.close()
            self.handle = nil
        }

        func replay(into writer: MaskWriter) async throws -> Int {
            guard !entries.isEmpty else { return 0 }
            let reader = try FileHandle(forReadingFrom: url)
            defer { try? reader.close() }
            for entry in entries.reversed() {
                try Task.checkCancellation()
                try reader.seek(toOffset: entry.offset)
                guard let data = try reader.read(upToCount: entry.length),
                      data.count == entry.length,
                      let mask = CIImage(data: data, options: [.colorSpace: NSNull()])
                else { throw GenerationError.frameConversionFailed }
                try await writer.append(mask, at: entry.time)
            }
            return entries.count
        }
    }

    private final class MaskWriter {
        private let writer: AVAssetWriter
        private let input: AVAssetWriterInput
        private let adaptor: AVAssetWriterInputPixelBufferAdaptor
        private let geometry: SourceGeometry
        private let context: CIContext

        init(destinationURL: URL, geometry: SourceGeometry, nominalFPS: Int, context: CIContext) throws {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
            self.geometry = geometry
            self.context = context
            let fps = max(1, nominalFPS)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: geometry.writerWidth,
                AVVideoHeightKey: geometry.writerHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoQualityKey: 1.0,
                    AVVideoExpectedSourceFrameRateKey: fps,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoMaxKeyFrameIntervalKey: max(1, fps / 2),
                ],
            ])
            input.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: geometry.writerWidth,
                kCVPixelBufferHeightKey as String: geometry.writerHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ])
            guard writer.canAdd(input) else { throw GenerationError.writerSetupFailed }
            writer.add(input)
        }

        func start() throws {
            guard writer.startWriting() else { throw writer.error ?? GenerationError.writerSetupFailed }
            writer.startSession(atSourceTime: .zero)
        }

        func append(_ mask: CIImage, at time: CMTime) async throws {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                if writer.status == .failed { throw writer.error ?? GenerationError.writeFailed }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard let pool = adaptor.pixelBufferPool else { throw GenerationError.writerSetupFailed }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw GenerationError.writerSetupFailed }
            context.render(mask, to: buffer, bounds: geometry.writerRect,
                           colorSpace: CGColorSpaceCreateDeviceGray())
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? GenerationError.appendFailed
            }
        }

        func finish(at time: CMTime) async throws {
            input.markAsFinished()
            writer.endSession(atSourceTime: time)
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? GenerationError.writeFailed }
        }

        func cancel() { writer.cancelWriting() }
    }

    private enum Frame {
        case pixelBuffer(CVPixelBuffer)
        case cgImage(CGImage)

        var image: CIImage {
            switch self {
            case .pixelBuffer(let buffer): CIImage(cvPixelBuffer: buffer)
            case .cgImage(let image): CIImage(cgImage: image)
            }
        }

        func requestHandler(orientation: CGImagePropertyOrientation) -> ImageRequestHandler {
            switch self {
            case .pixelBuffer(let buffer): ImageRequestHandler(buffer, orientation: orientation)
            case .cgImage(let image): ImageRequestHandler(image, orientation: orientation)
            }
        }
    }

    private final class MaskProcessor {
        private let tracker: ForegroundTracker
        private let segmenter: Segmenter?
        private let selectionPoint: CGPoint
        private let orientation: CGImagePropertyOrientation
        private var previousMask: CIImage?
        private var consecutiveFailures = 0

        init(
            context: CIContext,
            segmenter: Segmenter?,
            selectionPoint: CGPoint,
            orientation: CGImagePropertyOrientation
        ) {
            tracker = ForegroundTracker(context: context)
            self.segmenter = segmenter
            self.selectionPoint = selectionPoint
            self.orientation = orientation
        }

        func mask(_ frame: Frame) async throws -> CIImage {
            do {
                let mask = if let segmenter {
                    try await segmenter(frame.image, selectionPoint)
                } else {
                    try await tracker.mask(
                        frame,
                        orientation: orientation,
                        initialPoint: selectionPoint
                    )
                }
                previousMask = mask
                consecutiveFailures = 0
                return mask
            } catch {
                try Task.checkCancellation()
                consecutiveFailures += 1
                guard consecutiveFailures <= 4, let previousMask else {
                    throw GenerationError.noSubject
                }
                return previousMask
            }
        }
    }

    private final class ForegroundTracker {
        private let context: CIContext
        private var previousMask: CIImage?

        init(context: CIContext) {
            self.context = context
        }

        func mask(
            _ frame: Frame,
            orientation: CGImagePropertyOrientation,
            initialPoint: CGPoint
        ) async throws -> CIImage {
            let handler = frame.requestHandler(orientation: orientation)
            guard let observation = try await handler.perform(GenerateForegroundInstanceMaskRequest())
            else { throw GenerationError.noSubject }
            let instance: Int
            if let previousMask {
                guard let matched = bestInstance(in: observation, previousMask: previousMask) else {
                    throw GenerationError.noSubject
                }
                instance = matched
            } else {
                let point = Vision.NormalizedPoint(
                    x: min(1, max(0, initialPoint.x)),
                    y: 1 - min(1, max(0, initialPoint.y))
                )
                guard let selected = observation.instanceAtPoint(point).first else {
                    throw GenerationError.noSubject
                }
                instance = selected
            }
            let instances = IndexSet(integer: instance)
            previousMask = CIImage(
                cvPixelBuffer: try observation.generateMask(for: instances),
                options: [.colorSpace: NSNull()]
            )
            return CIImage(
                cvPixelBuffer: try observation.generateScaledMask(for: instances, scaledToImageFrom: handler),
                options: [.colorSpace: NSNull()]
            )
        }

        private func bestInstance(
            in observation: InstanceMaskObservation,
            previousMask: CIImage
        ) -> Int? {
            observation.allInstances.compactMap { instance -> (Int, Double)? in
                guard let buffer = try? observation.generateMask(for: IndexSet(integer: instance)) else {
                    return nil
                }
                let candidate = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
                let previous = previousMask.extent.size == candidate.extent.size
                    ? previousMask
                    : previousMask.transformed(by: CGAffineTransform(
                        scaleX: candidate.extent.width / previousMask.extent.width,
                        y: candidate.extent.height / previousMask.extent.height
                    ))
                let intersection = candidate.applyingFilter(
                    "CIMinimumCompositing",
                    parameters: [kCIInputBackgroundImageKey: previous]
                )
                let union = candidate.applyingFilter(
                    "CIMaximumCompositing",
                    parameters: [kCIInputBackgroundImageKey: previous]
                )
                let unionArea = average(union)
                guard unionArea > 0 else { return nil }
                return (instance, average(intersection) / unionArea)
            }.max(by: { $0.1 < $1.1 }).flatMap { $0.1 > 0 ? $0.0 : nil }
        }

        private func average(_ image: CIImage) -> Double {
            let average = image.applyingFilter(
                "CIAreaAverage",
                parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)]
            )
            var value: Float = 0
            context.render(
                average,
                toBitmap: &value,
                rowBytes: MemoryLayout<Float>.size,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .Rf,
                colorSpace: nil
            )
            return Double(value)
        }
    }

    private struct SourceGeometry {
        let rawRect: CGRect
        let writerRect: CGRect
        let displayToRaw: CGAffineTransform
        let orientation: CGImagePropertyOrientation
        let writerWidth: Int
        let writerHeight: Int

        init(naturalSize: CGSize, preferredTransform: CGAffineTransform) {
            let width = max(2, Int(abs(naturalSize.width).rounded()))
            let height = max(2, Int(abs(naturalSize.height).rounded()))
            rawRect = CGRect(x: 0, y: 0, width: width, height: height)
            let transformed = rawRect.applying(preferredTransform)
            let displayHeight = max(2, abs(transformed.height))
            let normalized = preferredTransform.concatenating(CGAffineTransform(
                translationX: -transformed.minX,
                y: -transformed.minY
            ))
            let rawToDisplay = Self.flipY(CGFloat(height))
                .concatenating(normalized)
                .concatenating(Self.flipY(displayHeight))
            displayToRaw = rawToDisplay.inverted()
            orientation = Self.orientation(for: preferredTransform)
            writerWidth = max(2, (width / 2) * 2)
            writerHeight = max(2, (height / 2) * 2)
            writerRect = CGRect(x: 0, y: 0, width: writerWidth, height: writerHeight)
        }

        func output(_ mask: CIImage) -> CIImage {
            mask.transformed(by: displayToRaw)
                .cropped(to: rawRect)
                .cropped(to: writerRect)
        }

        private static func flipY(_ height: CGFloat) -> CGAffineTransform {
            CGAffineTransform(translationX: 0, y: height).scaledBy(x: 1, y: -1)
        }

        private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
            switch (
                Int(transform.a.rounded()), Int(transform.b.rounded()),
                Int(transform.c.rounded()), Int(transform.d.rounded())
            ) {
            case (0, 1, -1, 0): .right
            case (0, -1, 1, 0): .left
            case (-1, 0, 0, -1): .down
            case (-1, 0, 0, 1): .upMirrored
            case (1, 0, 0, -1): .downMirrored
            case (0, 1, 1, 0): .leftMirrored
            case (0, -1, -1, 0): .rightMirrored
            default: .up
            }
        }
    }
}
