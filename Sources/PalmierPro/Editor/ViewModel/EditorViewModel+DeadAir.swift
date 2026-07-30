import AppKit

enum DeadAirMaskResolver {
    static func mask(
        for clip: Clip,
        in group: MulticamSource?,
        maskForMedia: (String) -> [Bool]?
    ) -> [Bool]? {
        guard let group,
              let member = group.member(mediaRef: clip.mediaRef) else {
            return maskForMedia(clip.mediaRef)
        }
        guard clip.mediaType == .audio, !group.mics.isEmpty else { return nil }

        let cellSeconds = VoiceActivity.chunkDuration
        var masks: [[Bool]] = []
        for mic in group.mics {
            guard let mask = maskForMedia(mic.mediaRef), !mask.isEmpty else { return nil }
            let shift = Int((mic.sync.offsetSeconds / cellSeconds).rounded())
            var shifted = [Bool](repeating: true, count: max(0, mask.count + shift))
            for (i, dead) in mask.enumerated() where i + shift >= 0 && i + shift < shifted.count {
                shifted[i + shift] = dead
            }
            masks.append(shifted)
        }

        let groupMask = (0..<(masks.map(\.count).max() ?? 0)).map { i in
            masks.allSatisfy { i >= $0.count || $0[i] }
        }
        let shift = Int((member.sync.offsetSeconds / cellSeconds).rounded())
        if shift > 0 { return Array(groupMask.dropFirst(shift)) }
        if shift < 0 { return [Bool](repeating: false, count: -shift) + groupMask }
        return groupMask
    }
}

/// Dead-air removal: maps SpeechMaskStore spans onto timeline ranges and ripple-deletes them.
extension EditorViewModel {

    func setMinimumSilenceDuration(_ seconds: Double) {
        guard let settings = SilenceRemovalSettings(
            minimumPauseSeconds: seconds,
            speechPaddingSeconds: silenceRemovalSettings.speechPaddingSeconds
        ) else { return }
        silenceRemovalSettings = settings
    }

    func setSpeechPaddingDuration(_ seconds: Double) {
        guard let settings = SilenceRemovalSettings(
            minimumPauseSeconds: silenceRemovalSettings.minimumPauseSeconds,
            speechPaddingSeconds: seconds
        ) else { return }
        silenceRemovalSettings = settings
    }

    /// The dead-air span under `timelineFrame` in `clip`, as a timeline range. Nil when the frame isn't dead air.
    func deadAirSpanRange(clip: Clip, atTimelineFrame frame: Int) -> FrameRange? {
        deadAirRanges(for: clip).first { $0.start <= frame && frame < $0.end }
    }

    /// Every dead-air span visible within `clip`, as timeline ranges.
    func deadAirRanges(
        for clip: Clip,
        settings: SilenceRemovalSettings? = nil
    ) -> [FrameRange] {
        let effectiveSettings = settings ?? silenceRemovalSettings
        return deadAirSourceRanges(for: clip, settings: effectiveSettings).compactMap {
            timelineRange(clip: clip, sourceStart: $0.lowerBound, sourceEnd: $0.upperBound)
        }
    }

    /// Dead-air ranges grouped by track; each track ripples its own spans.
    func allDeadAir(
        settings: SilenceRemovalSettings? = nil
    ) -> [(trackIndex: Int, ranges: [FrameRange])] {
        let effectiveSettings = settings ?? silenceRemovalSettings
        var out: [(Int, [FrameRange])] = []
        for (ti, track) in timeline.tracks.enumerated() where track.type == .audio {
            let ranges = track.clips.flatMap { deadAirRanges(for: $0, settings: effectiveSettings) }
            if !ranges.isEmpty { out.append((ti, ranges)) }
        }
        return out
    }

    func removeDeadAir(clipId: String, atTimelineFrame frame: Int) {
        guard let loc = findClip(id: clipId) else { return }
        let clip = timeline.tracks[loc.trackIndex].clips[loc.clipIndex]
        guard let range = deadAirSpanRange(clip: clip, atTimelineFrame: frame) else { return }
        if case .refused(let reason) = rippleDeleteRangesOnTrack(trackIndex: loc.trackIndex, ranges: [range]) {
            NSSound.beep()
            Log.editor.notice("remove dead air blocked: \(reason)")
        }
    }

    /// Ripples every dead-air span within selected clips on one track or in one linked A/V unit.
    @discardableResult
    func removeDeadAir(
        clipIds: [String],
        settings: SilenceRemovalSettings
    ) -> (sections: Int, removedFrames: Int, refusal: String?)? {
        let targets = clipIds.compactMap { id -> (trackIndex: Int, clip: Clip)? in
            guard let loc = findClip(id: id) else { return nil }
            return (loc.trackIndex, timeline.tracks[loc.trackIndex].clips[loc.clipIndex])
        }
        guard targets.count == clipIds.count, !targets.isEmpty else { return nil }

        let trackIndices = Set(targets.map(\.trackIndex))
        let anchorTrackIndex: Int
        let anchorClips: [Clip]
        if trackIndices.count == 1, let onlyTrack = trackIndices.first {
            anchorTrackIndex = onlyTrack
            anchorClips = targets.map(\.clip)
        } else {
            let linkGroups = targets.compactMap { $0.clip.linkGroupId }
            guard linkGroups.count == targets.count, Set(linkGroups).count == 1 else {
                return (0, 0, "Selected clips must share one track or belong to one linked A/V unit.")
            }
            anchorTrackIndex = trackIndices
                .filter { timeline.tracks[$0].type == .audio }
                .min() ?? trackIndices.min()!
            anchorClips = targets.filter { $0.trackIndex == anchorTrackIndex }.map(\.clip)
        }

        let ranges = RippleEngine.mergeRanges(
            anchorClips.flatMap { deadAirRanges(for: $0, settings: settings) }
        )
        guard !ranges.isEmpty else { return nil }
        switch rippleDeleteRangesOnTrack(trackIndex: anchorTrackIndex, ranges: ranges) {
        case .ok(let report):
            return (ranges.count, report.removedFrames, nil)
        case .refused(let reason):
            NSSound.beep()
            Log.editor.notice("remove dead air blocked: \(reason)")
            return (0, 0, reason)
        }
    }

    /// Ripples dead air per-track, updating ranges between passes. Stops if a track refuses.
    @discardableResult
    func removeAllDeadAir(
        settings: SilenceRemovalSettings? = nil
    ) -> (sections: Int, removedFrames: Int, refusal: String?)? {
        let effectiveSettings = settings ?? silenceRemovalSettings
        return undo.perform("Remove Dead Air") { () -> (sections: Int, removedFrames: Int, refusal: String?)? in
            var sections = 0
            var removedFrames = 0
            var refusal: String?
            for _ in timeline.tracks.indices {
                guard let next = allDeadAir(settings: effectiveSettings).first else { break }
                switch rippleDeleteRangesOnTrack(trackIndex: next.trackIndex, ranges: next.ranges) {
                case .ok(let report):
                    sections += next.ranges.count
                    removedFrames += report.removedFrames
                case .refused(let reason):
                    refusal = reason
                    NSSound.beep()
                    Log.editor.notice("remove dead air blocked: \(reason)")
                }
                if refusal != nil { break }
            }
            guard sections > 0 || refusal != nil else { return nil }
            return (sections, removedFrames, refusal)
        }
    }

    func deadAirSourceRanges(
        for clip: Clip,
        settings: SilenceRemovalSettings
    ) -> [Range<Double>] {
        guard let mask = DeadAirMaskResolver.mask(
            for: clip,
            in: multicamGroup(of: clip),
            maskForMedia: { mediaVisualCache.deadAirMask(for: $0, settings: settings) }
        ), !mask.isEmpty else { return [] }
        let visibleStart = Double(clip.trimStartFrame)
        let visibleEnd = Double(clip.trimStartFrame + clip.sourceFramesConsumed)
        return SilenceRemovalPlanner.visibleRemovableRanges(
            from: mask,
            visibleSourceRange: visibleStart..<visibleEnd,
            framesPerSecond: timeline.fps,
            settings: settings
        )
    }

    private func timelineRange(clip: Clip, sourceStart: Double, sourceEnd: Double) -> FrameRange? {
        let s0 = max(sourceStart, Double(clip.trimStartFrame))
        let s1 = min(sourceEnd, Double(clip.trimStartFrame + clip.sourceFramesConsumed))
        guard s1 > s0, clip.speed > 0 else { return nil }
        let t0 = Double(clip.startFrame) + (s0 - Double(clip.trimStartFrame)) / clip.speed
        let t1 = Double(clip.startFrame) + (s1 - Double(clip.trimStartFrame)) / clip.speed
        let range = FrameRange(start: Int(t0.rounded()), end: Int(t1.rounded()))
        return range.length > 0 ? range : nil
    }
}
