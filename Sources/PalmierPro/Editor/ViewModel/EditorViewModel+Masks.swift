import CoreMedia
import Foundation

enum MaskSession: Equatable {
    case idle
    case selecting(clipId: String)
    case generating(clipId: String, progress: Double)
    case previewing(clipId: String)
    case failed(clipId: String, message: String)
}

extension EditorViewModel {
    enum ClipMaskError: LocalizedError {
        case unavailable
        case invalidPoint
        case invalidFrame
        case invalidControls
        case busy
        case stale

        var errorDescription: String? {
            switch self {
            case .unavailable: "The selected video or project is unavailable."
            case .invalidPoint: "Select a point inside the source image."
            case .invalidFrame: "The tracking frame must be inside the clip."
            case .invalidControls: "The mask controls are outside their supported range."
            case .busy: "Another mask is already being created."
            case .stale: "The clip or project changed before the mask was ready."
            }
        }
    }

    var maskPointSelectionClipId: String? {
        guard case .selecting(let clipId) = maskSession else { return nil }
        return clipId
    }

    var maskPreviewClipId: String? {
        guard case .previewing(let clipId) = maskSession else { return nil }
        return clipId
    }

    func maskProgress(for clipId: String) -> Double? {
        guard case .generating(clipId, let progress) = maskSession else { return nil }
        return progress
    }

    func maskError(for clipId: String) -> String? {
        guard case .failed(clipId, let message) = maskSession else { return nil }
        return message
    }

    @discardableResult
    func generateMask(
        clipId: String,
        point: MaskNormalizedPoint,
        atFrame requestedFrame: Int? = nil,
        isApplied: Bool,
        inverted: Bool = false,
        feather: Double = 0,
        expansion: Double = 0
    ) async throws -> ClipMask {
        guard maskGenerationTask == nil else { throw ClipMaskError.busy }
        guard point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y)
        else { throw ClipMaskError.invalidPoint }
        guard feather.isFinite, (0...100).contains(feather),
              expansion.isFinite, (-50...50).contains(expansion)
        else { throw ClipMaskError.invalidControls }
        guard let targetProjectURL = projectURL,
              let clip = clipFor(id: clipId),
              clip.mediaType == .video,
              clip.speed.isFinite,
              clip.speed > 0,
              let sourceURL = mediaResolver.expectedURL(for: clip.mediaRef)
        else { throw ClipMaskError.unavailable }

        let frame = requestedFrame ?? min(max(activeFrame, clip.startFrame), clip.endFrame - 1)
        guard (clip.startFrame..<clip.endFrame).contains(frame) else {
            throw ClipMaskError.invalidFrame
        }
        let fps = Double(max(1, timeline.fps))
        let selectionTime = CMTime(
            seconds: (Double(clip.trimStartFrame) + Double(frame - clip.startFrame) * clip.speed) / fps,
            preferredTimescale: 600_000
        )
        let sourceStart = CMTime(
            seconds: Double(clip.trimStartFrame) / fps,
            preferredTimescale: 600_000
        )
        let sourceEnd = CMTime(
            seconds: (Double(clip.trimStartFrame) + Double(clip.durationFrames) * clip.speed) / fps,
            preferredTimescale: 600_000
        )
        guard selectionTime.isNumeric,
              sourceStart.isNumeric,
              sourceEnd.isNumeric,
              selectionTime >= sourceStart,
              selectionTime < sourceEnd
        else {
            throw ClipMaskError.invalidFrame
        }

        let selection = MaskSelection(point: point, sourceTime: MediaTime(selectionTime))
        let sourceRange = MediaTimeRange(CMTimeRange(start: sourceStart, end: sourceEnd))
        let maskId = UUID().uuidString
        let stagedURL = FileIO.temporaryFileURL(pathExtension: "mov")
        let mediaRef = clip.mediaRef
        maskSession = .generating(clipId: clipId, progress: 0)

        let task = Task { @MainActor in
            let output = try await AppleMaskGenerator.generate(
                sourceURL: sourceURL,
                sourceRange: sourceRange,
                selection: selection,
                destinationURL: stagedURL,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard case .generating(clipId, _) = self?.maskSession else { return }
                        self?.maskSession = .generating(clipId: clipId, progress: progress)
                    }
                }
            )
            try validateMaskCommit(clipId: clipId, mediaRef: mediaRef, projectURL: targetProjectURL)
            _ = try await commitStagedProjectFile(
                stagedURL,
                directoryName: Project.maskDirectoryName,
                filename: MediaResolver.maskFilename(for: maskId),
                expectedProjectURL: targetProjectURL
            )
            try Task.checkCancellation()
            try validateMaskCommit(clipId: clipId, mediaRef: mediaRef, projectURL: targetProjectURL)
            let mask = ClipMask(
                id: maskId,
                sourceMediaRef: mediaRef,
                sourceRange: output,
                selection: selection,
                isApplied: isApplied,
                inverted: inverted,
                feather: feather,
                expansion: expansion
            )
            maskSession = isApplied ? .idle : .previewing(clipId: clipId)
            mutateClips(ids: [clipId], actionName: "Create Mask") { $0.mask = mask }
            return mask
        }
        maskGenerationTask = task
        defer { maskGenerationTask = nil }
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            maskSession = error is CancellationError
                ? .idle
                : .failed(clipId: clipId, message: error.localizedDescription)
            throw error
        }
    }

    private func validateMaskCommit(clipId: String, mediaRef: String, projectURL expected: URL) throws {
        guard projectURL?.standardizedFileURL == expected.standardizedFileURL,
              clipFor(id: clipId)?.mediaRef == mediaRef
        else { throw ClipMaskError.stale }
    }

    func cancelMaskGeneration() { maskGenerationTask?.cancel() }

    func beginMaskPointSelection(clipId: String) {
        guard activePreviewTab == .timeline,
              clipFor(id: clipId)?.mediaType == .video,
              maskGenerationTask == nil
        else { return }
        cancelChromaKeySampling()
        cropEditingActive = false
        pause()
        maskSession = .selecting(clipId: clipId)
        videoEngine?.rebuild()
    }

    func cancelMaskPointSelection() {
        guard case .selecting = maskSession else { return }
        maskSession = .idle
    }

    func commitMaskPointSelection(clipId: String, point: MaskNormalizedPoint) {
        guard maskPointSelectionClipId == clipId else { return }
        let frame = activeFrame
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await generateMask(
                clipId: clipId,
                point: point,
                atFrame: frame,
                isApplied: false
            )
        }
    }

    func showMaskPreview(clipId: String) {
        guard clipFor(id: clipId)?.mask != nil else { return }
        maskSession = .previewing(clipId: clipId)
        videoEngine?.rebuild()
    }

    func hideMaskPreview(clipId: String) {
        guard maskPreviewClipId == clipId else { return }
        maskSession = .idle
        videoEngine?.rebuild()
    }

    func applyMaskAsAlpha(clipId: String) {
        guard clipFor(id: clipId)?.mask?.isApplied == false else { return }
        maskSession = .idle
        commitClipProperty(clipId: clipId, actionName: "Remove Background") {
            $0.mask?.isApplied = true
        }
    }

    func removeMask(clipId: String) {
        guard clipFor(id: clipId)?.mask != nil else { return }
        if maskPreviewClipId == clipId { maskSession = .idle }
        mutateClips(ids: [clipId], actionName: "Remove Mask") { $0.mask = nil }
    }
}
