import CoreGraphics
import Foundation

/// Maps a point in the preview (top-left origin, view space) to the topmost visible
/// clip drawn under it at the current playhead frame, for click-to-select.
@MainActor
enum PreviewHitTester {
    static func clipID(at point: CGPoint, viewSize: CGSize, editor: EditorViewModel) -> String? {
        let videoRect = videoContentRect(in: viewSize, timeline: editor.timeline)
        guard videoRect.width > 0, videoRect.height > 0 else { return nil }
        let frame = editor.playheadState.timelineFrame

        // Text draws above all video; within text, higher track index is on top, so keep the last hit.
        var topText: String?
        for track in editor.timeline.tracks where !track.hidden {
            for clip in track.clips where clip.mediaType == .text {
                guard clip.contains(timelineFrame: frame), clip.opacityAt(frame: frame) > 0.01 else { continue }
                if textHit(clip, frame: frame, point: point, videoRect: videoRect) { topText = clip.id }
            }
        }
        if let topText { return topText }

        // Video/image: track 0 is topmost (see CompositionBuilder), so first hit wins.
        for track in editor.timeline.tracks where track.type != .audio && !track.hidden {
            for clip in track.clips where clip.mediaType != .text && clip.mediaType != .audio {
                guard clip.contains(timelineFrame: frame), clip.opacityAt(frame: frame) > 0.01 else { continue }
                if videoHit(clip, frame: frame, point: point, videoRect: videoRect) { return clip.id }
            }
        }
        return nil
    }

    private static func textHit(_ clip: Clip, frame: Int, point: CGPoint, videoRect: CGRect) -> Bool {
        transformedHit(clip, frame: frame, point: point, videoRect: videoRect, crop: nil)
    }

    private static func videoHit(_ clip: Clip, frame: Int, point: CGPoint, videoRect: CGRect) -> Bool {
        transformedHit(clip, frame: frame, point: point, videoRect: videoRect, crop: clip.cropAt(frame: frame))
    }

    private static func transformedHit(
        _ clip: Clip,
        frame: Int,
        point: CGPoint,
        videoRect: CGRect,
        crop: Crop?
    ) -> Bool {
        guard let source = sourcePoint(at: point, clip: clip, frame: frame, videoRect: videoRect) else {
            return false
        }
        let crop = crop ?? Crop()
        return source.x >= crop.left && source.x <= 1 - crop.right
            && source.y >= crop.top && source.y <= 1 - crop.bottom
    }

    static func videoContentRect(in viewSize: CGSize, timeline: Timeline) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let videoAspect = CGFloat(timeline.width) / CGFloat(timeline.height)
        let viewAspect = viewSize.width / viewSize.height
        let w: CGFloat, h: CGFloat
        if viewAspect > videoAspect {
            h = viewSize.height; w = h * videoAspect
        } else {
            w = viewSize.width; h = w / videoAspect
        }
        return CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
    }

    static func sourceNormalizedPoint(
        at point: CGPoint,
        viewSize: CGSize,
        clip: Clip,
        frame: Int,
        timeline: Timeline
    ) -> MaskNormalizedPoint? {
        let videoRect = videoContentRect(in: viewSize, timeline: timeline)
        guard let source = sourcePoint(at: point, clip: clip, frame: frame, videoRect: videoRect) else {
            return nil
        }
        let crop = clip.cropAt(frame: frame)
        guard source.x >= crop.left, source.x <= 1 - crop.right,
              source.y >= crop.top, source.y <= 1 - crop.bottom
        else { return nil }
        return MaskNormalizedPoint(x: source.x, y: source.y)
    }

    private static func sourcePoint(
        at point: CGPoint,
        clip: Clip,
        frame: Int,
        videoRect: CGRect
    ) -> CGPoint? {
        let transform = clip.transformAt(frame: frame)
        let rect = clipFrame(transform, videoRect: videoRect)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let radians = transform.rotation * .pi / 180
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        var x = (dx * cos(radians) + dy * sin(radians)) / rect.width + 0.5
        var y = (-dx * sin(radians) + dy * cos(radians)) / rect.height + 0.5
        if transform.flipHorizontal { x = 1 - x }
        if transform.flipVertical { y = 1 - y }
        return CGPoint(x: x, y: y)
    }

    static func clipFrame(_ t: Transform, videoRect: CGRect) -> CGRect {
        let tl = t.topLeft
        return CGRect(
            x: videoRect.origin.x + tl.x * videoRect.width,
            y: videoRect.origin.y + tl.y * videoRect.height,
            width: t.width * videoRect.width,
            height: t.height * videoRect.height
        )
    }
}
