import Foundation

enum AppLanguage: Hashable, Identifiable, Sendable {
    case system
    case language(String)

    static let defaultsKey = "appLanguage"

    var id: String {
        switch self {
        case .system: "system"
        case .language(let identifier): identifier
        }
    }

    var identifier: String? {
        switch self {
        case .system: nil
        case .language(let identifier): identifier
        }
    }

    static func stored(in defaults: UserDefaults) -> AppLanguage {
        guard let identifier = defaults.string(forKey: defaultsKey), identifier != "system" else {
            return .system
        }
        return .language(identifier)
    }
}
