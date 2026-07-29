import SwiftUI

struct MaskTab: View {
    let clipId: String
    @Environment(EditorViewModel.self) private var editor

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            EditorPanelGroup("Mask", contentSpacing: AppTheme.Spacing.smMd) {
                content
            }
            .controlSize(.small)
            if let mask = clip?.mask { actions(mask) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if clip?.mask?.isApplied == false { editor.showMaskPreview(clipId: clipId) }
        }
    }

    private var clip: Clip? { editor.clipFor(id: clipId) }

    @ViewBuilder
    private var content: some View {
        if editor.maskPointSelectionClipId == clipId {
            Text("Click the object in the viewer. Tracking starts at the playhead.")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
            Button("Cancel") { editor.cancelMaskPointSelection() }
        } else if let progress = editor.maskProgress(for: clipId) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView(value: progress)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: AppTheme.FontSize.xs).monospacedDigit())
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            Button("Cancel") { editor.cancelMaskGeneration() }
        } else if let mask = clip?.mask {
            InspectorRow(label: "Invert") {
                Toggle("", isOn: Binding(
                    get: { clip?.mask?.inverted ?? false },
                    set: { value in
                        editor.commitClipProperty(clipId: clipId, actionName: "Invert Mask") {
                            $0.mask?.inverted = value
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Invert Mask")
            }
            valueRow(
                label: "Feather",
                value: mask.feather,
                range: 0...100,
                actionName: "Change Mask Feather"
            ) { $0.mask?.feather = $1 }
            valueRow(
                label: "Expand",
                value: mask.expansion,
                range: -50...50,
                actionName: "Change Mask Expansion"
            ) { $0.mask?.expansion = $1 }
        } else {
            Button("Select Object") { editor.beginMaskPointSelection(clipId: clipId) }
        }

        if let message = editor.maskError(for: clipId) {
            Text(message)
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Status.errorColor)
        }
    }

    private func actions(_ mask: ClipMask) -> some View {
        EditorPanelGroup("Actions", contentSpacing: AppTheme.Spacing.smMd) {
            if mask.isApplied {
                Button(editor.maskPreviewClipId == clipId ? "Stop Preview" : "Preview Mask") {
                    if editor.maskPreviewClipId == clipId {
                        editor.hideMaskPreview(clipId: clipId)
                    } else {
                        editor.showMaskPreview(clipId: clipId)
                    }
                }
            } else {
                Button("Remove Background") { editor.applyMaskAsAlpha(clipId: clipId) }
            }
            Button("Reselect Object") { editor.beginMaskPointSelection(clipId: clipId) }
            Button("Remove Mask", role: .destructive) { editor.removeMask(clipId: clipId) }
        }
        .controlSize(.small)
    }

    private func valueRow(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        actionName: String,
        modify: @escaping (inout Clip, Double) -> Void
    ) -> some View {
        InspectorRow(label: label) {
            ScrubbableNumberField(
                value: value,
                range: range,
                format: "%.0f",
                valueSuffix: " px",
                dragSensitivity: 0.25,
                fieldWidth: AppTheme.EditorPanel.numericFieldWidth,
                onChanged: { next in
                    editor.applyClipProperty(clipId: clipId) { modify(&$0, next) }
                }
            ) { next in
                editor.commitClipProperty(clipId: clipId, actionName: actionName) {
                    modify(&$0, next)
                }
            }
        }
    }
}
