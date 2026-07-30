import AppKit
import Foundation
import Testing
@testable import PalmierPro

@Suite("App appearance")
@MainActor
struct AppAppearanceTests {
    @Test func missingOrInvalidPreferenceUsesDarkAppearance() throws {
        let suiteName = "AppAppearanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppAppearance.stored(in: defaults) == .dark)

        defaults.set("sepia", forKey: AppAppearance.defaultsKey)
        #expect(AppAppearance.stored(in: defaults) == .dark)
    }

    @Test func storedPreferenceRoundTrips() throws {
        let suiteName = "AppAppearanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppAppearance.light.rawValue, forKey: AppAppearance.defaultsKey)
        #expect(AppAppearance.stored(in: defaults) == .light)

        defaults.set(AppAppearance.dark.rawValue, forKey: AppAppearance.defaultsKey)
        #expect(AppAppearance.stored(in: defaults) == .dark)
    }

    @Test func semanticPaletteInvertsBetweenAppearances() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))

        #expect(brightness(AppTheme.Background.surface, in: light) > brightness(AppTheme.Background.surface, in: dark))
        #expect(brightness(AppTheme.Text.primary, in: light) < brightness(AppTheme.Text.primary, in: dark))
        #expect(brightness(AppTheme.Accent.primaryNSColor, in: light) < brightness(AppTheme.Accent.primaryNSColor, in: dark))
    }

    @Test func lightPaletteMaintainsReadableContrast() throws {
        let light = try #require(NSAppearance(named: .aqua))

        #expect(brightness(AppTheme.Background.surface, in: light) < brightness(AppTheme.Background.raised, in: light))
        #expect(brightness(AppTheme.Background.raised, in: light) < brightness(AppTheme.Background.prominent, in: light))
        #expect(brightness(AppTheme.Background.prominent, in: light) < 1)
        #expect(contrastRatio(AppTheme.Text.tertiary, over: AppTheme.Background.surface, in: light) >= 4.5)
        #expect(contrastRatio(AppTheme.Text.muted, over: AppTheme.Background.surface, in: light) >= 3)
        #expect(contrastRatio(AppTheme.Border.divider, over: AppTheme.Background.surface, in: light) >= 3)
    }

    private func brightness(_ color: NSColor, in appearance: NSAppearance) -> CGFloat {
        let resolved = resolved(color, in: appearance)
        return resolved.redComponent * 0.2126
            + resolved.greenComponent * 0.7152
            + resolved.blueComponent * 0.0722
    }

    private func resolved(_ color: NSColor, in appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private func contrastRatio(_ foreground: NSColor, over background: NSColor, in appearance: NSAppearance) -> CGFloat {
        let foreground = resolved(foreground, in: appearance)
        let background = resolved(background, in: appearance)
        let alpha = foreground.alphaComponent
        let blended = [
            foreground.redComponent * alpha + background.redComponent * (1 - alpha),
            foreground.greenComponent * alpha + background.greenComponent * (1 - alpha),
            foreground.blueComponent * alpha + background.blueComponent * (1 - alpha),
        ]
        let foregroundLuminance = relativeLuminance(blended)
        let backgroundLuminance = relativeLuminance([
            background.redComponent,
            background.greenComponent,
            background.blueComponent,
        ])
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ components: [CGFloat]) -> CGFloat {
        let linear = components.map { component in
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
}
