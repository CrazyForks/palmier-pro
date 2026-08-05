import SwiftUI

struct AudioPreviewView: View {
    @Environment(EditorViewModel.self) private var editor
    let asset: MediaAsset

    @State private var samples: [Float] = []
    @State private var textBlock: AudioPreviewContent.TextBlock?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: AppTheme.Spacing.lg) {
                Spacer(minLength: AppTheme.Spacing.md)
                waveform
                    .frame(height: waveformHeight(in: geo.size))
                    .padding(.horizontal, AppTheme.Spacing.xl)
                if let textBlock {
                    textSection(textBlock.text)
                        .frame(maxHeight: textHeight(in: geo.size))
                        .padding(.horizontal, AppTheme.Spacing.xl)
                }
                Spacer(minLength: AppTheme.Spacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.Background.previewCanvasColor)
        .allowsHitTesting(false)
        .task(id: assetIdentity) {
            await loadContent()
        }
    }

    private var assetIdentity: String {
        "\(asset.id)|\(asset.url.path)|\(asset.generationInput?.prompt ?? "")|\(asset.generationInput?.lyrics ?? "")"
    }

    private var progress: CGFloat {
        let duration = max(0, editor.activePreviewDurationFrames)
        guard duration > 0 else { return 0 }
        let frame = editor.playheadState.sourceFrame
        return min(1, max(0, CGFloat(frame) / CGFloat(duration)))
    }

    private func waveformHeight(in size: CGSize) -> CGFloat {
        min(160, max(72, size.height * 0.28))
    }

    private func textHeight(in size: CGSize) -> CGFloat {
        min(160, max(64, size.height * 0.32))
    }

    private var waveform: some View {
        Group {
            if samples.isEmpty {
                Image(systemName: "waveform")
                    .font(.system(size: AppTheme.FontSize.display))
                    .foregroundStyle(AppTheme.MediaOverlay.mutedColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Canvas { context, size in
                    Self.drawWaveform(
                        samples: samples,
                        progress: progress,
                        in: size,
                        context: &context
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static let barWidth = AppTheme.Spacing.xxs
    private static let barGap = AppTheme.BorderWidth.thin

    private static func drawWaveform(
        samples: [Float],
        progress: CGFloat,
        in size: CGSize,
        context: inout GraphicsContext
    ) {
        guard size.width > 2, size.height > 2, !samples.isEmpty else { return }

        let step = barWidth + barGap
        let barCount = max(1, Int((size.width + barGap) / step))
        let midY = size.height / 2
        let maxBarHeight = size.height * 0.9
        let minBarHeight = AppTheme.BorderWidth.medium
        let progressX = size.width * progress
        let barColor = AppTheme.MediaOverlay.primaryColor

        for i in 0..<barCount {
            let start = i * samples.count / barCount
            let end = max(start + 1, (i + 1) * samples.count / barCount)
            var loudest: Float = 1
            for s in start..<min(end, samples.count) {
                if samples[s] < loudest { loudest = samples[s] }
            }
            let amplitude = CGFloat(1 - loudest)
            let barHeight = max(minBarHeight, amplitude * maxBarHeight)
            let x = CGFloat(i) * step
            let rect = CGRect(
                x: x,
                y: midY - barHeight / 2,
                width: barWidth,
                height: barHeight
            )
            let opacity = x + barWidth <= progressX
                ? AppTheme.Opacity.prominent
                : AppTheme.Opacity.medium
            context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(barColor.opacity(opacity)))
        }

        let playhead = CGRect(x: progressX - 0.5, y: 0, width: 1, height: size.height)
        context.fill(Path(playhead), with: .color(AppTheme.MediaOverlay.primaryColor.opacity(AppTheme.Opacity.high)))
    }

    private func textSection(_ text: String) -> some View {
        ScrollView {
            Text(verbatim: text)
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(AppTheme.MediaOverlay.secondaryColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    @MainActor
    private func loadContent() async {
        let url = asset.url
        let generationInput = asset.generationInput
        async let transcriptTask: String? = Task.detached(priority: .utility) {
            if let local = TranscriptCache.cachedOnDisk(for: url)?.text {
                return local
            }
            return await TranscriptCache.shared.cachedCloudTranscript(
                for: url,
                range: nil,
                language: nil
            )?.text
        }.value

        async let waveformTask: [Float]? = editor.mediaVisualCache.ensureWaveform(for: asset)

        let transcript = await transcriptTask
        if Task.isCancelled { return }
        textBlock = AudioPreviewContent.text(
            transcript: transcript,
            generationInput: generationInput
        )

        if let waveform = await waveformTask, !Task.isCancelled {
            samples = waveform
        }
    }
}
