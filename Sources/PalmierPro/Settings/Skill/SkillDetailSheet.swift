import SwiftUI

struct SkillDetailSheet: View {
    let skillID: String
    var catalogEntry: SkillCatalogEntry? = nil

    @Bindable private var store = SkillStore.shared
    @Bindable private var catalog = SkillCatalog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var draft = ""
    @State private var originalDraft = ""
    @State private var confirmingDelete = false
    @State private var isUpdating = false
    @State private var isInstalling = false
    @State private var editingTitle = false
    @State private var draftTitle = ""
    @State private var copyToast: CopyToast?
    @State private var showingSaveError = false
    @State private var failedExit: ExitAction?
    @State private var remoteBody: String?
    @State private var bodyLoadFailed = false
    @FocusState private var titleFocused: Bool

    private enum ExitAction {
        case close, preview
    }

    private struct CopyToast: Equatable {
        let agentLabel: String
        let url: URL

        var displayPath: String {
            url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
    }

    private var skill: Skill? {
        store.skills.first { $0.id == skillID }
    }

    private var resolvedCatalogEntry: SkillCatalogEntry? {
        catalog.entry(id: skillID) ?? catalogEntry
    }

    private var deleteTitle: String {
        guard let skill else { return L10n.string("Delete skill?") }
        return L10n.string("Delete \u{201C}\(skill.name)\u{201D}?")
    }

    var body: some View {
        Group {
            if let skill {
                content(skill)
            } else if let entry = resolvedCatalogEntry {
                previewContent(entry)
            } else {
                Text(L10n.string("Skill unavailable."))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .frame(width: AppTheme.Settings.skillDetailWidth)
                    .frame(minHeight: AppTheme.Settings.skillDetailMinHeight)
                    .overlay(alignment: .topTrailing) {
                        closeButton
                            .padding(.horizontal, AppTheme.Spacing.xlXxl)
                            .padding(.vertical, AppTheme.Spacing.mdLg)
                    }
            }
        }
        .interactiveDismissDisabled((editing && draft != originalDraft) || editingTitle)
        .onExitCommand {
            if editingTitle {
                cancelTitleEditing()
            } else {
                close()
            }
        }
        .alert(L10n.string("Unable to save skill"), isPresented: $showingSaveError) {
            Button(L10n.string("Keep Editing"), role: .cancel) { failedExit = nil }
            if failedExit != nil {
                Button(L10n.string("Discard Changes"), role: .destructive) { discardChanges() }
            }
        } message: {
            Text(L10n.string("Add nonempty name and description fields to the skill frontmatter."))
        }
    }

    private func content(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            header(skill)
            Divider().overlay(AppTheme.Border.subtleColor)

            if editing {
                editContent
            } else {
                ScrollView {
                    viewContent(
                        description: skill.description,
                        instructions: store.body(for: skill.id) ?? ""
                    )
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
        .frame(width: AppTheme.Settings.skillDetailWidth)
        .frame(minHeight: AppTheme.Settings.skillDetailMinHeight)
        .background(AppTheme.Background.prominentColor)
        .overlay(alignment: .top) {
            if let toast = copyToast {
                copyToastBanner(toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: AppTheme.Anim.transition), value: copyToast)
        .confirmationDialog(
            deleteTitle,
            isPresented: $confirmingDelete,
            titleVisibility: .visible,
            presenting: self.skill
        ) { skill in
            Button(L10n.string("Delete \u{201C}\(skill.name)\u{201D}"), role: .destructive) {
                store.delete(skill)
                dismiss()
            }
            Button(L10n.string("Keep Skill"), role: .cancel) {}
        } message: { skill in
            Text(L10n.string("This permanently removes \(displayPath(skill))."))
        }
    }

    private func previewContent(_ entry: SkillCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            previewHeader(entry)
            Divider().overlay(AppTheme.Border.subtleColor)

            ScrollView {
                Group {
                    if let remoteBody {
                        viewContent(description: entry.description, instructions: remoteBody)
                    } else if bodyLoadFailed {
                        SkillEmptyState(
                            systemName: "exclamationmark.triangle",
                            title: L10n.string("Skill unavailable."),
                            message: entry.description,
                            actionTitle: L10n.string("Try Again"),
                            action: { Task { await loadRemoteBody(entry) } }
                        )
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(L10n.string("Loading community skills"))
                    }
                }
                .padding(AppTheme.Spacing.xlXxl)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .themedSurface(AppTheme.Background.raisedColor, cornerRadius: AppTheme.Radius.md)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .padding(.horizontal, AppTheme.Spacing.xlXxl)
            .padding(.top, AppTheme.Spacing.mdLg)
            .padding(.bottom, AppTheme.Spacing.xlXxl)
        }
        .frame(width: AppTheme.Settings.skillDetailWidth)
        .frame(minHeight: AppTheme.Settings.skillDetailMinHeight)
        .background(AppTheme.Background.prominentColor)
        .task(id: "\(entry.path)\0\(entry.sha)") {
            await loadRemoteBody(entry)
        }
    }

    private func previewHeader(_ entry: SkillCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(entry.name)
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
                        .accessibilityLabel(L10n.string("Working on \(entry.name)"))
                } else {
                    Button(L10n.string("Install")) { install(entry) }
                        .buttonStyle(.capsule(.prominent))
                        .disabled(remoteBody == nil)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xlXxl)
        .padding(.vertical, AppTheme.Spacing.mdLg)
    }

    private func header(_ skill: Skill) -> some View {
        let state = SkillCommunityState.resolve(skill, store: store, catalog: catalog)
        let dirty = editing && draft != originalDraft

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                titleView(skill)
                Spacer(minLength: AppTheme.Spacing.md)
                closeButton
            }

            HStack(spacing: AppTheme.Spacing.smMd) {
                Text(verbatim: state.map { L10n.string(key: $0.label) } ?? L10n.string("Local"))
                    .font(.system(size: AppTheme.FontSize.xs))
                    .foregroundStyle(state?.color ?? AppTheme.Text.tertiaryColor)

                Spacer(minLength: AppTheme.Spacing.md)

                if state == .update, !editing {
                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(L10n.string("Updating \(skill.name)"))
                    } else {
                        Button(L10n.string("Update")) { update(skill) }
                            .buttonStyle(.capsule(.secondary, fill: AnyShapeStyle(AppTheme.Background.raisedColor)))
                    }
                }

                SkillExternalAgentMenu(skill: skill, store: store) { agent, url in
                    copyToast = CopyToast(agentLabel: agent.label, url: url)
                }
                .disabled(editing)

                if dirty {
                    Button(L10n.string("Save Changes")) {
                        commitDraftIfDirty()
                    }
                    .buttonStyle(.capsule(.prominent))
                    .keyboardShortcut("s", modifiers: .command)
                }

                Button(editing ? L10n.string("Preview") : L10n.string("Edit")) {
                    toggleEditing(skill)
                }
                .buttonStyle(.capsule(.secondary, fill: AnyShapeStyle(AppTheme.Background.raisedColor)))

                actionsMenu(skill)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xlXxl)
        .padding(.vertical, AppTheme.Spacing.mdLg)
    }

    private var closeButton: some View {
        Button(action: close) {
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
    private func titleView(_ skill: Skill) -> some View {
        if editingTitle {
            TextField(L10n.string("Skill name"), text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: AppTheme.FontSize.xl, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .accessibilityLabel(L10n.string("Skill name"))
                .focused($titleFocused)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .themedSurface(
                    AppTheme.Background.raisedColor,
                    cornerRadius: AppTheme.Radius.xs,
                    border: AppTheme.Accent.link.opacity(AppTheme.Opacity.medium)
                )
                .onSubmit { commitTitle() }
                .onChange(of: titleFocused) { if !titleFocused { commitTitle() } }
        } else {
            Text(skill.name)
                .font(.system(size: AppTheme.FontSize.xl, weight: AppTheme.FontWeight.regular))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .lineLimit(1)
        }
    }

    private func actionsMenu(_ skill: Skill) -> some View {
        Menu {
            Button(L10n.string("Rename Skill"), systemImage: "pencil") {
                draftTitle = skill.name
                editingTitle = true
                titleFocused = true
            }
            .disabled(editing)
            Button(L10n.string("Show in Finder"), systemImage: "folder") {
                store.reveal(skill.path)
            }
            Divider()
            Button(L10n.string("Delete Skill"), systemImage: "trash", role: .destructive) {
                confirmingDelete = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
                .padding(AppTheme.Spacing.xs)
                .hoverHighlight(cornerRadius: AppTheme.Radius.sm)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(L10n.string("More skill actions"))
        .help(L10n.string("More skill actions"))
    }

    private func toggleEditing(_ skill: Skill) {
        if editing {
            finish(.preview)
            return
        }

        commitTitle()
        draft = (try? String(contentsOf: skill.path, encoding: .utf8)) ?? ""
        originalDraft = draft
        editing = true
    }

    private func update(_ skill: Skill) {
        guard !editing, let entry = catalog.entry(id: skill.id) else { return }
        isUpdating = true
        Task {
            _ = await store.install(entry)
            isUpdating = false
        }
    }

    private func install(_ entry: SkillCatalogEntry) {
        guard !isInstalling else { return }
        isInstalling = true
        Task {
            _ = await store.install(entry)
            isInstalling = false
        }
    }

    private func loadRemoteBody(_ entry: SkillCatalogEntry) async {
        bodyLoadFailed = false
        remoteBody = nil
        do {
            let body = try await SkillCatalog.fetchBody(path: entry.path)
            guard !Task.isCancelled, isCurrentPreview(entry) else { return }
            remoteBody = body
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, isCurrentPreview(entry) else { return }
            bodyLoadFailed = true
            Log.agent.error("skill preview load failed (\(entry.id)): \(error.localizedDescription)")
        }
    }

    private func isCurrentPreview(_ entry: SkillCatalogEntry) -> Bool {
        guard let current = resolvedCatalogEntry else { return false }
        return current.path == entry.path && current.sha == entry.sha
    }

    @discardableResult
    private func commitDraftIfDirty(onFailure exit: ExitAction? = nil) -> Bool {
        guard draft != originalDraft else { return true }
        guard let skill, store.save(skill, raw: draft) else {
            failedExit = exit
            showingSaveError = true
            return false
        }
        failedExit = nil
        originalDraft = draft
        return true
    }

    private func commitTitle() {
        guard editingTitle, let skill else { return }
        editingTitle = false
        store.rename(skill, to: draftTitle)
    }

    private func cancelTitleEditing() {
        editingTitle = false
        draftTitle = skill?.name ?? ""
    }

    private func close() {
        finish(.close)
    }

    private func finish(_ action: ExitAction) {
        guard skill != nil else {
            dismiss()
            return
        }
        guard commitDraftIfDirty(onFailure: action) else { return }
        commitTitle()
        switch action {
        case .close: dismiss()
        case .preview: editing = false
        }
    }

    private func discardChanges() {
        guard let action = failedExit else { return }
        failedExit = nil
        draft = originalDraft
        switch action {
        case .close: dismiss()
        case .preview: editing = false
        }
    }

    private func displayPath(_ skill: Skill) -> String {
        skill.path.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func viewContent(description: String, instructions: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(L10n.string("Description"))
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(description)
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
                    text: instructions,
                    proseFont: .system(size: AppTheme.FontSize.smMd),
                    blockSpacing: AppTheme.Spacing.sm
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editContent: some View {
        TextEditor(text: $draft)
            .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
            .foregroundStyle(AppTheme.Text.primaryColor)
            .accessibilityLabel(L10n.string("Skill instructions"))
            .scrollContentBackground(.hidden)
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Background.raisedColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .padding(AppTheme.Spacing.xlXxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyToastBanner(_ toast: CopyToast) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Status.successColor)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(L10n.string("Added to \(toast.agentLabel)"))
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(toast.displayPath)
                    .font(.system(size: AppTheme.FontSize.xxs))
                    .foregroundStyle(AppTheme.Text.mutedColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: AppTheme.Spacing.md)

            Button(L10n.string("Open")) {
                store.reveal(toast.url)
                copyToast = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
            .foregroundStyle(AppTheme.Accent.link)
        }
        .padding(.horizontal, AppTheme.Spacing.mdLg)
        .padding(.vertical, AppTheme.Spacing.smMd)
        .frame(maxWidth: AppTheme.Settings.skillToastWidth)
        .themedSurface(
            AppTheme.Background.prominentColor,
            cornerRadius: AppTheme.Radius.md,
            border: AppTheme.Border.primaryColor,
            borderWidth: AppTheme.BorderWidth.hairline
        )
        .shadow(AppTheme.Shadow.lg)
        .padding(.top, AppTheme.Spacing.lgXl)
        .onTapGesture { copyToast = nil }
        .task(id: toast) {
            try? await Task.sleep(for: AppTheme.Settings.skillToastDuration)
            guard !Task.isCancelled else { return }
            copyToast = nil
        }
    }
}
