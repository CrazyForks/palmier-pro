import SwiftUI

struct SpeechTab: View {
    @Environment(EditorViewModel.self) private var editor

    private enum SilenceDurationControl {
        case minimumPause
        case speechPadding
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
                    speakersSection
                    silenceSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if let phase = editor.speakerIdentifyPhase {
                AppTheme.Background.surfaceColor.opacity(AppTheme.Opacity.prominent)
                GeneratingOverlay(label: phase, size: .preview)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var speakersSection: some View {
        EditorPanelGroup("Speakers", contentInsets: sectionContentInsets) {
            InspectorRow(
                label: "Mark Speakers",
                labelHelp: "Tints waveforms by speaker. Voices are matched across clips using cloud transcripts.",
                labelAlignment: .leading,
                onReset: { editor.markSpeakers = false }
            ) {
                Toggle("", isOn: Binding(
                    get: { editor.markSpeakers },
                    set: { editor.markSpeakers = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Mark Speakers")
            }
            Button(editor.projectSpeakers.isEmpty ? "Identify Speakers" : "Refresh") {
                editor.identifySpeakers(transcribeMissing: true)
            }
            .buttonStyle(.capsule(.secondary))
            .disabled(editor.speakerIdentifyInFlight)
            .help("Matches voices across clips, transcribing untranscribed timeline clips first (uses credits). Transcripts and voice fingerprints are cached, so re-runs are fast.")
            if let error = editor.speakerIdentifyError {
                Text(error)
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Status.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !editor.projectSpeakers.isEmpty {
                Text("Labels")
                    .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .padding(.top, AppTheme.Spacing.xs)
            }
            ForEach(editor.projectSpeakers) { speaker in
                HStack(spacing: AppTheme.Spacing.sm) {
                    ColorPicker("", selection: Binding(
                        get: { editor.projectSpeakers.first(where: { $0.id == speaker.id })?.color ?? speaker.color },
                        set: { editor.setSpeakerColor(id: speaker.id, color: $0) }
                    ))
                    .labelsHidden()
                    .controlSize(.small)
                    TextField("Name", text: Binding(
                        get: { editor.projectSpeakers.first(where: { $0.id == speaker.id })?.name ?? speaker.name },
                        set: { editor.renameSpeaker(id: speaker.id, name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: AppTheme.FontSize.sm))
                    Button {
                        editor.removeSpeaker(id: speaker.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    }
                    .buttonStyle(.plain)
                    .help("Removes this label and tint. Identify recreates it if the voice is still present.")
                }
            }
        }
    }

    private var silenceSection: some View {
        EditorPanelGroup("Silence Detection", contentInsets: sectionContentInsets) {
            InspectorRow(
                label: "Mark Silence",
                labelHelp: "Speech is detected on-device in the background. Dims quiet, speech-free spans on timeline waveforms.",
                labelAlignment: .leading,
                onReset: { editor.markDeadAir = false }
            ) {
                Toggle("", isOn: Binding(
                    get: { editor.markDeadAir },
                    set: { editor.markDeadAir = $0 }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Mark Silence")
            }
            if editor.speechAnalyzingCount > 0 {
                HStack(spacing: AppTheme.Spacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                    Text(editor.speechAnalyzingCount == 1
                        ? "Detecting speech…"
                        : "Detecting speech in \(editor.speechAnalyzingCount) files…")
                        .font(.system(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.mutedColor)
                }
            }
            silenceTimingControls
            removeSilenceRow
        }
    }

    private var silenceTimingControls: some View {
        Group {
            InspectorRow(
                label: "Minimum Pause",
                labelHelp: "Ignores speech-free pauses shorter than this.",
                labelAlignment: .leading,
                onReset: {
                    editor.setMinimumSilenceDuration(SilenceRemovalSettings.default.minimumPauseSeconds)
                }
            ) {
                durationControl(.minimumPause)
            }
            InspectorRow(
                label: "Speech Padding",
                labelHelp: "Keeps this much audio before and after detected speech.",
                labelAlignment: .leading,
                onReset: {
                    editor.setSpeechPaddingDuration(SilenceRemovalSettings.default.speechPaddingSeconds)
                }
            ) {
                durationControl(.speechPadding)
            }
        }
    }

    private func durationControl(_ control: SilenceDurationControl) -> some View {
        let label = control == .minimumPause ? "Minimum Pause" : "Speech Padding"
        let value = control == .minimumPause
            ? editor.silenceRemovalSettings.minimumPauseSeconds
            : editor.silenceRemovalSettings.speechPaddingSeconds
        let range = control == .minimumPause
            ? SilenceRemovalSettings.minimumPauseRange
            : SilenceRemovalSettings.speechPaddingRange
        let step = control == .minimumPause ? 0.05 : 0.025
        return ScrubbableNumberField(
            value: value,
            range: range,
            displayMultiplier: 1_000,
            format: "%.0f",
            valueSuffix: " ms",
            dragSensitivity: 10,
            dragValueAdjustment: { candidate in
                min(range.upperBound, max(range.lowerBound, (candidate / step).rounded() * step))
            },
            onChanged: { setDuration($0, for: control) },
            onCommit: { setDuration($0, for: control) }
        )
        .accessibilityLabel(label)
    }

    private func setDuration(_ seconds: Double, for control: SilenceDurationControl) {
        switch control {
        case .minimumPause:
            editor.setMinimumSilenceDuration(seconds)
        case .speechPadding:
            editor.setSpeechPaddingDuration(seconds)
        }
    }

    private var removeSilenceRow: some View {
        let count = editor.allDeadAir().reduce(0) { $0 + $1.ranges.count }
        return HStack(spacing: AppTheme.Spacing.sm) {
            Button("Remove") { editor.removeAllDeadAir() }
                .buttonStyle(.capsule(.secondary))
                .disabled(count == 0)
                .help("Ripple-deletes every silent section; downstream clips close the gaps.")
            if count > 0 {
                Text(count == 1 ? "1 section" : "\(count) sections")
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }
        }
    }

    private var sectionContentInsets: EdgeInsets {
        EdgeInsets(
            top: AppTheme.Spacing.smMd,
            leading: AppTheme.Spacing.mdLg,
            bottom: AppTheme.Spacing.smMd,
            trailing: AppTheme.Spacing.mdLg
        )
    }
}
