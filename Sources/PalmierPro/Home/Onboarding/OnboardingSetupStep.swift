import SwiftUI

struct OnboardingSetupStep: View {
    @Bindable private var store = SkillStore.shared
    @Bindable private var catalog = SkillCatalog.shared
    @Bindable private var appState = AppState.shared
    @State private var installing: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                OnboardingTitle(L10n.string("Recommended setup"))
                OnboardingDetail(
                    L10n.string("Optional picks that help the agent and external tools work better. You can change these later in Settings.")
                )
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                if catalog.isLoading && recommendedEntries.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppTheme.Spacing.smMd)
                        .accessibilityLabel(L10n.string("Loading…"))
                } else {
                    ForEach(recommendedEntries) { entry in
                        skillRow(entry)
                    }
                }
                mcpRow
            }
        }
        .task {
            await store.reloadInBackground()
            await catalog.refresh()
        }
    }

    private var recommendedEntries: [SkillCatalogEntry] {
        RecommendedSkills.ids.compactMap { catalog.entry(id: $0) }
    }

    private func skillRow(_ entry: SkillCatalogEntry) -> some View {
        let installed = store.skills.contains { $0.id == entry.id }
        return OnboardingSetupRow(
            icon: "book.closed.fill",
            title: entry.name,
            detail: entry.description,
            recommended: true
        ) {
            if installing.contains(entry.id) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.string("Installing \(entry.name)"))
            } else if installed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Status.successColor)
                    .accessibilityLabel(L10n.string("Installed"))
            } else {
                Button(L10n.string("Install")) {
                    install(entry)
                }
                .buttonStyle(.capsule(.prominent, size: .small))
            }
        }
    }

    private var mcpRow: some View {
        OnboardingSetupRow(
            icon: "puzzlepiece.extension.fill",
            title: L10n.string("MCP Server"),
            detail: L10n.string("Lets external clients like Cursor, Claude Desktop, Claude Code, and Codex edit your timeline."),
            recommended: true
        ) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Button(L10n.string("Setup")) {
                    HelpWindowController.shared.show(tab: .mcp)
                }
                .buttonStyle(.capsule(
                    .secondary,
                    size: .small,
                    fill: AnyShapeStyle(AppTheme.Background.raisedColor)
                ))

                Toggle(
                    String(),
                    isOn: Binding(
                        get: { appState.mcpService?.isRunning ?? MCPService.isEnabledPreference },
                        set: { appState.setMCPEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(L10n.string("MCP Server"))
            }
        }
    }

    private func install(_ entry: SkillCatalogEntry) {
        installing.insert(entry.id)
        Task {
            _ = await store.install(entry)
            installing.remove(entry.id)
        }
    }
}

private struct OnboardingSetupRow<Accessory: View>: View {
    let icon: String
    let title: String
    let detail: String
    let recommended: Bool
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: AppTheme.FontSize.smMd))
                .foregroundStyle(AppTheme.Accent.primary)
                .frame(width: AppTheme.IconSize.sm)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    Text(verbatim: title)
                        .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                        .lineLimit(1)
                    if recommended {
                        Text(L10n.string("(Recommended)"))
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                            .lineLimit(1)
                    }
                }
                Text(verbatim: detail)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory()
        }
        .padding(.horizontal, AppTheme.Spacing.smMd)
        .padding(.vertical, AppTheme.Spacing.smMd)
    }
}
