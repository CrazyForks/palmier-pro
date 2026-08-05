import Foundation

/// Skills highlighted during onboarding and in Settings › Community.
enum RecommendedSkills {
    static let ids: [String] = [
        "caption-templates",
    ]

    static func contains(_ id: String) -> Bool {
        ids.contains(id)
    }
}
