import SwiftUI

struct AppearancePane: View {
    @Bindable private var appearance = AppAppearanceStore.shared

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.mdLg) {
            ForEach(AppAppearance.allCases) { option in
                AppearanceOptionCard(
                    option: option,
                    isSelected: appearance.selection == option,
                    action: { appearance.selection = option }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AppearanceOptionCard: View {
    let option: AppAppearance
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.smMd) {
                AppearancePreview(option: option)
                    .aspectRatio(1.5, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .strokeBorder(
                                borderColor,
                                lineWidth: isSelected ? AppTheme.BorderWidth.thick : AppTheme.BorderWidth.thin
                            )
                    }

                Text(option.label)
                    .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(isSelected ? AppTheme.Text.primaryColor : AppTheme.Text.tertiaryColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("\(option.label) appearance")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var borderColor: Color {
        if isSelected { return AppTheme.Accent.primary }
        return isHovering ? AppTheme.Border.dividerColor : AppTheme.Border.subtleColor
    }
}

private struct AppearancePreview: View {
    let option: AppAppearance

    var body: some View {
        ZStack {
            switch option {
            case .system:
                AppearancePreviewScene(palette: .light)
                AppearancePreviewScene(palette: .dark)
                    .mask {
                        HStack(spacing: 0) {
                            Color.clear
                            Color.white
                        }
                    }
            case .light:
                AppearancePreviewScene(palette: .light)
            case .dark:
                AppearancePreviewScene(palette: .dark)
            }
        }
    }
}

private struct AppearancePreviewScene: View {
    let palette: AppearancePreviewPalette

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .bottom) {
                palette.canvas

                VStack(spacing: height * 0.045) {
                    Capsule()
                        .fill(palette.strongLine)
                        .frame(width: width * 0.28, height: max(height * 0.045, 3))
                    Capsule()
                        .fill(palette.line)
                        .frame(width: width * 0.48, height: max(height * 0.025, 2))
                    Spacer(minLength: 0)
                }
                .padding(.top, height * 0.18)

                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { row in
                        VStack(alignment: .leading, spacing: height * 0.035) {
                            Capsule()
                                .fill(palette.strongLine)
                                .frame(width: width * 0.28, height: max(height * 0.045, 3))
                            Capsule()
                                .fill(palette.line)
                                .frame(width: width * 0.45, height: max(height * 0.025, 2))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, width * 0.08)
                        .frame(maxHeight: .infinity)

                        if row < 2 {
                            Rectangle()
                                .fill(palette.divider)
                                .frame(height: AppTheme.BorderWidth.hairline)
                        }
                    }
                }
                .frame(width: width * 0.78, height: height * 0.62)
                .background(palette.panel)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: AppTheme.Radius.md,
                        topTrailingRadius: AppTheme.Radius.md
                    )
                )
            }
        }
    }
}

private struct AppearancePreviewPalette {
    let canvas: Color
    let panel: Color
    let line: Color
    let strongLine: Color
    let divider: Color

    static let light = AppearancePreviewPalette(
        canvas: Color(white: 0.92),
        panel: Color(white: 0.99),
        line: Color.black.opacity(0.08),
        strongLine: Color.black.opacity(0.15),
        divider: Color.black.opacity(0.08)
    )

    static let dark = AppearancePreviewPalette(
        canvas: Color(white: 0.25),
        panel: Color(white: 0.13),
        line: Color.white.opacity(0.17),
        strongLine: Color.white.opacity(0.30),
        divider: Color.white.opacity(0.10)
    )
}
