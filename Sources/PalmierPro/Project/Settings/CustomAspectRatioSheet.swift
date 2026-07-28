import SwiftUI

struct CustomAspectRatioContext: Identifiable {
    let id = UUID()
    let timelineID: String
    let width: Int
    let height: Int
}

struct CustomAspectRatioSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EditorViewModel.self) private var editor

    let context: CustomAspectRatioContext

    @State private var horizontalText: String
    @State private var verticalText: String

    init(context: CustomAspectRatioContext) {
        self.context = context
        let components = CanvasAspectRatio.displayLabel(width: context.width, height: context.height).split(separator: ":")
        _horizontalText = State(initialValue: components.first.map(String.init) ?? "")
        _verticalText = State(initialValue: components.last.map(String.init) ?? "")
    }

    var body: some View {
        let validation = validation
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            Text("Custom Aspect Ratio")
                .font(.system(size: AppTheme.FontSize.xl, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)

            Text("Changing the ratio preserves the shorter edge.")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)

            HStack(alignment: .bottom, spacing: AppTheme.Spacing.md) {
                ratioField("Width", text: $horizontalText)
                Text(":")
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .padding(.bottom, AppTheme.Spacing.sm)
                ratioField("Height", text: $verticalText)
            }

            if let resolution = validation.resolution {
                LabeledContent("Resolution", value: "\(resolution.width) × \(resolution.height)")
                    .font(.system(size: AppTheme.FontSize.sm).monospacedDigit())
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            } else if let message = validation.message {
                Text(message)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Status.errorColor)
            }

            HStack(spacing: AppTheme.Spacing.md) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    guard let resolution = validation.resolution else { return }
                    editor.applyTimelineSettings(fps: editor.timeline.fps, width: resolution.width, height: resolution.height)
                    dismiss()
                }
                    .buttonStyle(.capsule(.prominent, size: .regular))
                    .keyboardShortcut(.defaultAction)
                    .disabled(validation.resolution == nil)
            }
        }
        .padding(AppTheme.Spacing.xlXxl)
        .frame(width: AppTheme.EditorPanel.defaultWidth)
    }

    private func ratioField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(label)
                .font(.system(size: AppTheme.FontSize.xs))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: AppTheme.FontSize.md).monospacedDigit())
                .frame(width: AppTheme.EditorPanel.numericFieldWidth)
                .accessibilityLabel("Aspect ratio \(label.lowercased())")
        }
    }

    private var validation: (resolution: (width: Int, height: Int)?, message: String?) {
        guard editor.activeTimelineId == context.timelineID,
              (editor.timeline.width, editor.timeline.height) == (context.width, context.height) else {
            return (nil, "The timeline settings changed. Close this sheet and try again.")
        }
        do {
            let ratio = try CanvasAspectRatio("\(horizontalText):\(verticalText)")
            return (try ratio.resolution(shortEdge: min(context.width, context.height)), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}
