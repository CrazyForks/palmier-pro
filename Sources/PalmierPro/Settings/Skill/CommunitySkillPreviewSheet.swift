import SwiftUI

struct CommunitySkillPreviewSheet: View {
    let entry: SkillCatalogEntry
    let onInstalled: (String) -> Void

    @Bindable private var store = SkillStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var preview: SkillCatalogPreview?
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var isInstalling = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            header
            Divider().overlay(AppTheme.Border.subtleColor)
            bodyContent
        }
        .frame(width: AppTheme.Settings.skillDetailWidth)
        .frame(minHeight: AppTheme.Settings.skillDetailMinHeight)
        .background(AppTheme.Background.prominentColor)
        .task(id: entry.id) {
            await loadPreview()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(verbatim: preview?.name ?? entry.name)
                    .font(.system(size: AppTheme.FontSize.xl, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .lineLimit(1)
                Spacer(minLength: AppTheme.Spacing.md)
                closeButton
            }

            HStack(spacing: AppTheme.Spacing.smMd) {
                Text(L10n.string("Available"))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)

                Spacer(minLength: AppTheme.Spacing.md)

                if isInstalling {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(L10n.string("Installing \(entry.name)"))
                } else {
                    Button(L10n.string("Install")) { install() }
                        .buttonStyle(.capsule(.prominent))
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xlXxl)
        .padding(.vertical, AppTheme.Spacing.mdLg)
    }

    private var closeButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
                .padding(AppTheme.Spacing.xs)
                .hoverHighlight(cornerRadius: AppTheme.Radius.sm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.string("Close"))
        .help(L10n.string("Close"))
    }

    @ViewBuilder
    private var bodyContent: some View {
        if isLoading {
            HStack(spacing: AppTheme.Spacing.smMd) {
                ProgressView().controlSize(.small)
                Text(L10n.string("Loading skill preview…"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.string("Loading skill preview"))
        } else if let loadError {
            VStack(spacing: AppTheme.Spacing.smMd) {
                Text(L10n.string("Unable to load skill preview."))
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(verbatim: loadError)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L10n.string("Try Again")) {
                    Task { await loadPreview() }
                }
                .buttonStyle(.capsule(.secondary, fill: AnyShapeStyle(AppTheme.Background.raisedColor)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(AppTheme.Spacing.xlXxl)
        } else if let preview {
            ScrollView {
                previewContent(preview)
                    .padding(AppTheme.Spacing.xlXxl)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .themedSurface(AppTheme.Background.raisedColor, cornerRadius: AppTheme.Radius.md)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .padding(.horizontal, AppTheme.Spacing.xlXxl)
            .padding(.top, AppTheme.Spacing.mdLg)
            .padding(.bottom, AppTheme.Spacing.xlXxl)
        }
    }

    private func previewContent(_ preview: SkillCatalogPreview) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(L10n.string("Description"))
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(verbatim: preview.description)
                    .font(.system(size: AppTheme.FontSize.smMd))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(AppTheme.Border.subtleColor)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(L10n.string("Instructions"))
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                MarkdownText(
                    text: preview.body,
                    proseFont: .system(size: AppTheme.FontSize.smMd),
                    blockSpacing: AppTheme.Spacing.sm
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadPreview() async {
        isLoading = true
        loadError = nil
        preview = nil
        do {
            preview = try await SkillCatalog.loadPreview(for: entry)
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            isLoading = false
            Log.agent.error(
                "skill preview \(entry.id) failed: \(error.localizedDescription)"
            )
        }
    }

    private func install() {
        guard !isInstalling else { return }
        isInstalling = true
        Task {
            let installed = await store.install(entry)
            isInstalling = false
            guard !Task.isCancelled, installed else { return }
            onInstalled(entry.id)
        }
    }
}
