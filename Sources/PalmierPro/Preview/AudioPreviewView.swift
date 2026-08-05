import SwiftUI

struct AudioPreviewView: View {
    @Environment(EditorViewModel.self) private var editor
    let asset: MediaAsset

    @State private var samples: [Float] = []
    @State private var lines: [DisplayLine] = []

    private struct DisplayLine: Identifiable, Equatable {
        let id: Int
        let text: String
        let start: Double?
        let end: Double?
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if lines.isEmpty {
                    Spacer(minLength: AppTheme.Spacing.lg)
                    waveform
                        .frame(height: emptyWaveformHeight(in: geo.size))
                        .padding(.horizontal, AppTheme.Spacing.xxl)
                    Spacer(minLength: AppTheme.Spacing.lg)
                } else {
                    transcriptPanel
                    waveform
                        .frame(height: AppTheme.Spacing.xxl + AppTheme.Spacing.sm)
                        .padding(.horizontal, AppTheme.Spacing.xxl)
                        .padding(.top, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.lg)
                }
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
        "\(asset.id)|\(asset.url.path)"
    }

    private var progress: CGFloat {
        let duration = max(0, editor.activePreviewDurationFrames)
        guard duration > 0 else { return 0 }
        let frame = editor.playheadState.sourceFrame
        return min(1, max(0, CGFloat(frame) / CGFloat(duration)))
    }

    private var currentTimeSeconds: Double {
        let fps = max(1, editor.timeline.fps)
        return Double(editor.playheadState.sourceFrame) / Double(fps)
    }

    private var activeLineIndex: Int {
        if lines.contains(where: { $0.start != nil }) {
            let timed = lines.compactMap { line -> AudioPreviewContent.TimedLine? in
                guard let start = line.start, let end = line.end else { return nil }
                return .init(text: line.text, start: start, end: end)
            }
            return AudioPreviewContent.activeTimedLineIndex(time: currentTimeSeconds, lines: timed)
        }
        return AudioPreviewContent.activeLineIndex(
            progress: Double(progress),
            lineCount: lines.count
        )
    }

    private func emptyWaveformHeight(in size: CGSize) -> CGFloat {
        min(AppTheme.Spacing.xxl * 4, max(AppTheme.Spacing.xxl * 2, size.height * 0.22))
    }

    private var transcriptPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let isActive = index == activeLineIndex
                        Text(verbatim: line.text)
                            .font(.system(
                                size: AppTheme.FontSize.mdLg,
                                weight: isActive
                                    ? AppTheme.FontWeight.semibold
                                    : AppTheme.FontWeight.regular
                            ))
                            .foregroundStyle(
                                isActive
                                    ? AppTheme.MediaOverlay.primaryColor
                                    : AppTheme.MediaOverlay.tertiaryColor
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.vertical, AppTheme.Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .onChange(of: activeLineIndex) { _, index in
                withAnimation(.easeInOut(duration: AppTheme.Anim.transition)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(activeLineIndex, anchor: .center)
            }
        }
    }

    private var waveform: some View {
        Group {
            if samples.isEmpty {
                Image(systemName: "waveform")
                    .font(.system(size: AppTheme.FontSize.xl))
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
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(barColor.opacity(opacity))
            )
        }
    }

    @MainActor
    private func loadContent() async {
        let url = asset.url
        async let transcriptTask: TranscriptionResult? = Task.detached(priority: .utility) {
            if let local = TranscriptCache.cachedOnDisk(for: url) {
                return local
            }
            return await TranscriptCache.shared.cachedCloudTranscript(
                for: url,
                range: nil,
                language: nil
            )
        }.value

        async let waveformTask: [Float]? = editor.mediaVisualCache.ensureWaveform(for: asset)

        let transcript = await transcriptTask
        if Task.isCancelled { return }

        let timed = AudioPreviewContent.timedLines(from: transcript)
        if timed.contains(where: { $0.end > $0.start }) {
            lines = timed.enumerated().map {
                DisplayLine(id: $0.offset, text: $0.element.text, start: $0.element.start, end: $0.element.end)
            }
        } else if let block = AudioPreviewContent.text(transcript: transcript?.text) {
            lines = block.lines.enumerated().map {
                DisplayLine(id: $0.offset, text: $0.element, start: nil, end: nil)
            }
        } else {
            lines = []
        }

        if let waveform = await waveformTask, !Task.isCancelled {
            samples = waveform
        }
    }
}
