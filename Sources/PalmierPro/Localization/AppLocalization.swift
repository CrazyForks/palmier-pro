import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class AppLocalization {
    static let shared = AppLocalization()

    let activeLanguage: AppLanguage
    let activeIdentifier: String
    let activeLocale: Locale
    let availableLanguages: [AppLanguage]

    var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.id, forKey: AppLanguage.defaultsKey)
        }
    }

    var requiresRestart: Bool {
        selection != activeLanguage
    }

    private let defaults: UserDefaults
    private let localizedBundle: Bundle

    init(defaults: UserDefaults = .standard, resourceBundle: Bundle = BundledResource.bundle) {
        self.defaults = defaults

        let identifiers = Self.localizationIdentifiers(in: resourceBundle)
        availableLanguages = identifiers.map(AppLanguage.language)

        let storedLanguage = AppLanguage.stored(in: defaults)
        let validLanguage: AppLanguage
        if let identifier = storedLanguage.identifier, identifiers.contains(identifier) {
            validLanguage = storedLanguage
        } else {
            validLanguage = .system
        }

        activeLanguage = validLanguage
        selection = validLanguage
        activeIdentifier = Self.resolveIdentifier(for: validLanguage, available: identifiers)
        activeLocale = Locale(identifier: activeIdentifier)
        localizedBundle = Self.localizedBundle(
            for: activeIdentifier,
            resourceBundle: resourceBundle
        )
    }

    func string(_ keyAndValue: String.LocalizationValue) -> String {
        String(
            localized: keyAndValue,
            bundle: localizedBundle,
            locale: activeLocale
        )
    }

    func string(key: String, defaultValue: String? = nil) -> String {
        localizedBundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }

    func displayName(for language: AppLanguage) -> String {
        guard let identifier = language.identifier else {
            return string("System Language")
        }
        let locale = Locale(identifier: identifier)
        return locale.localizedString(forIdentifier: identifier) ?? identifier
    }

    private static func localizationIdentifiers(in bundle: Bundle) -> [String] {
        bundle.localizations
            .filter { $0 != "Base" }
            .sorted { lhs, rhs in
                let lhsName = Locale(identifier: lhs).localizedString(forIdentifier: lhs) ?? lhs
                let rhsName = Locale(identifier: rhs).localizedString(forIdentifier: rhs) ?? rhs
                return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
            }
    }

    private static func resolveIdentifier(for language: AppLanguage, available: [String]) -> String {
        if let identifier = language.identifier {
            return identifier
        }
        return Bundle.preferredLocalizations(
            from: available,
            forPreferences: Locale.preferredLanguages
        ).first ?? "en"
    }

    private static func localizedBundle(for identifier: String, resourceBundle: Bundle) -> Bundle {
        guard let url = resourceBundle.url(forResource: identifier, withExtension: "lproj"),
              let bundle = Bundle(url: url) else {
            return resourceBundle
        }
        return bundle
    }
}

extension View {
    func appLocalization() -> some View {
        environment(\.locale, AppLocalization.shared.activeLocale)
    }
}

@MainActor
enum L10n {
    nonisolated static func key(_ value: StaticString) -> String {
        value.description
    }

    static func string(_ keyAndValue: String.LocalizationValue) -> String {
        AppLocalization.shared.string(keyAndValue)
    }

    static func string(key: String, defaultValue: String? = nil) -> String {
        AppLocalization.shared.string(key: key, defaultValue: defaultValue)
    }
}
