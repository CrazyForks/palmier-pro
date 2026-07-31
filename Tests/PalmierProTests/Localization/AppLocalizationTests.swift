import Foundation
import Testing
@testable import PalmierPro

@Suite("App localization")
@MainActor
struct AppLocalizationTests {
    @Test func bundledEnglishLocalizationIsAvailable() throws {
        try withDefaults { defaults in
            let localization = AppLocalization(defaults: defaults)

            #expect(localization.availableLanguages.contains(.language("en")))
            #expect(localization.string("System Language") == "System Language")
            #expect(localization.string(key: "System Language") == "System Language")
            #expect(localization.string(key: "Export Queue") == "Export Queue")
            #expect(
                BundledResource.bundle.localizedString(
                    forKey: "CFBundleTypeName",
                    value: nil,
                    table: "InfoPlist"
                ) == "Palmier Project"
            )
        }
    }

    @Test func validStoredLanguageBecomesActiveAtLaunch() throws {
        try withDefaults { defaults in
            defaults.set("en", forKey: AppLanguage.defaultsKey)

            let localization = AppLocalization(defaults: defaults)

            #expect(localization.activeLanguage == .language("en"))
            #expect(localization.activeIdentifier == "en")
            #expect(localization.selection == .language("en"))
            #expect(!localization.requiresRestart)
        }
    }

    @Test func storedLanguageIdentifiersAreCanonicalized() throws {
        try withDefaults { defaults in
            defaults.set("EN", forKey: AppLanguage.defaultsKey)

            let localization = AppLocalization(defaults: defaults)

            #expect(localization.activeLanguage == .language("en"))
            #expect(defaults.string(forKey: AppLanguage.defaultsKey) == "en")
        }
    }

    @Test func unsupportedStoredLanguageFallsBackToSystem() throws {
        try withDefaults { defaults in
            defaults.set("not-a-bundled-language", forKey: AppLanguage.defaultsKey)

            let localization = AppLocalization(defaults: defaults, preferredLanguages: ["en"])

            #expect(localization.activeLanguage == .system)
            #expect(localization.activeIdentifier == "en")
            #expect(localization.selection == .system)
            #expect(defaults.string(forKey: AppLanguage.defaultsKey) == "system")
        }
    }

    @Test func selectingTheActiveSystemLanguageDoesNotRequireRestart() throws {
        try withDefaults { defaults in
            let localization = AppLocalization(defaults: defaults, preferredLanguages: ["en"])

            localization.selection = .language("en")

            #expect(defaults.string(forKey: AppLanguage.defaultsKey) == "en")
            #expect(!localization.requiresRestart)
        }
    }

    @Test func selectingAnotherLanguageRequiresRestart() throws {
        try withDefaults { defaults in
            let localization = AppLocalization(defaults: defaults, preferredLanguages: ["en"])

            localization.selection = .language("fr")

            #expect(defaults.string(forKey: AppLanguage.defaultsKey) == "fr")
            #expect(localization.requiresRestart)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "AppLocalizationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
