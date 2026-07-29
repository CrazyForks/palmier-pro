import Foundation
@testable import PalmierPro

enum Fixtures {
    static func clip(
        id: String = UUID().uuidString,
        mediaRef: String = "media-1",
        mediaType: ClipType = .video,
        start: Int,
        duration: Int,
        trimStart: Int = 0,
        trimEnd: Int = 0,
        speed: Double = 1.0,
        volume: Double = 1.0
    ) -> Clip {
        var c = Clip(mediaRef: mediaRef, startFrame: start, durationFrames: duration)
        c.id = id
        c.mediaType = mediaType
        c.sourceClipType = mediaType
        c.trimStartFrame = trimStart
        c.trimEndFrame = trimEnd
        c.speed = speed
        c.volume = volume
        return c
    }

    static func videoTrack(id: String = UUID().uuidString, clips: [Clip] = []) -> Track {
        var t = Track(type: .video, clips: clips)
        t.id = id
        return t
    }

    static func audioTrack(id: String = UUID().uuidString, clips: [Clip] = []) -> Track {
        var t = Track(type: .audio, clips: clips)
        t.id = id
        return t
    }

    static func timeline(fps: Int = 30, tracks: [Track] = []) -> Timeline {
        var t = Timeline()
        t.fps = fps
        t.tracks = tracks
        return t
    }

    static func mask(
        id: String = "mask-1",
        mediaRef: String = "pattern",
        applied: Bool = true,
        inverted: Bool = false,
        feather: Double = 0,
        expansion: Double = 0
    ) -> ClipMask {
        let start = MediaTime(value: 0, timescale: 30)
        return ClipMask(
            id: id,
            sourceMediaRef: mediaRef,
            sourceRange: MediaTimeRange(start: start, duration: MediaTime(value: 60, timescale: 30)),
            selection: MaskSelection(point: MaskNormalizedPoint(x: 0.25, y: 0.5), sourceTime: start),
            isApplied: applied,
            inverted: inverted,
            feather: feather,
            expansion: expansion
        )
    }
}
