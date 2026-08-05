import Foundation
import Testing
@testable import PalmierPro

@Suite("Default skills")
struct DefaultSkillsTests {
    @Test func includesCaptionTemplates() {
        #expect(DefaultSkills.ids.contains("caption-templates"))
    }

    @Test func pendingInstallsSkipsPresentSkills() {
        let catalog = [
            SkillCatalogEntry(
                id: "caption-templates",
                name: "caption-templates",
                description: "Style captions.",
                sha: "abc123abc123",
                path: "skills/caption-templates/SKILL.md"
            ),
            SkillCatalogEntry(
                id: "color-grading",
                name: "color-grading",
                description: "Grade clips.",
                sha: "def456def456",
                path: "skills/color-grading/SKILL.md"
            ),
        ]

        let pending = DefaultSkills.pendingInstalls(
            catalogEntries: catalog,
            presentIDs: ["caption-templates"]
        )

        #expect(pending.isEmpty)
    }

    @Test func pendingInstallsReturnsMissingDefaultsOnly() {
        let catalog = [
            SkillCatalogEntry(
                id: "caption-templates",
                name: "caption-templates",
                description: "Style captions.",
                sha: "abc123abc123",
                path: "skills/caption-templates/SKILL.md"
            ),
            SkillCatalogEntry(
                id: "color-grading",
                name: "color-grading",
                description: "Grade clips.",
                sha: "def456def456",
                path: "skills/color-grading/SKILL.md"
            ),
        ]

        let pending = DefaultSkills.pendingInstalls(
            catalogEntries: catalog,
            presentIDs: []
        )

        #expect(pending.map(\.id) == ["caption-templates"])
    }

    @Test func pendingInstallsIgnoresDefaultsAbsentFromCatalog() {
        let catalog = [
            SkillCatalogEntry(
                id: "color-grading",
                name: "color-grading",
                description: "Grade clips.",
                sha: "def456def456",
                path: "skills/color-grading/SKILL.md"
            ),
        ]

        let pending = DefaultSkills.pendingInstalls(
            catalogEntries: catalog,
            presentIDs: []
        )

        #expect(pending.isEmpty)
    }
}
