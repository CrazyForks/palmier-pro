import AppKit
import SwiftUI

struct MaskPointSamplerOverlayView: View {
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(AppTheme.Background.clearColor)
                .contentShape(Rectangle())
                .onHover { hovering in
                    (hovering ? NSCursor.crosshair : NSCursor.arrow).set()
                }
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        select(at: value.location, viewSize: geometry.size)
                    }
                )
        }
        .onDisappear { NSCursor.arrow.set() }
    }

    private func select(at point: CGPoint, viewSize: CGSize) {
        guard let clipId = editor.maskPointSelectionClipId,
              let clip = editor.clipFor(id: clipId),
              let normalized = PreviewHitTester.sourceNormalizedPoint(
                at: point,
                viewSize: viewSize,
                clip: clip,
                frame: editor.activeFrame,
                timeline: editor.timeline
              )
        else {
            NSSound.beep()
            return
        }
        editor.commitMaskPointSelection(clipId: clipId, point: normalized)
    }
}
