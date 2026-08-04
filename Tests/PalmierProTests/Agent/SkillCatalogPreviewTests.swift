import Testing
@testable import PalmierPro

@Suite("Skill catalog preview")
struct SkillCatalogPreviewTests {
    @Test func prefersFrontmatterOverCatalogMetadata() {
        let entry = SkillCatalogEntry(
            id: "cut-pacing",
            name: "Catalog Name",
            description: "Catalog description.",
            sha: "abc123",
            path: "skills/cut-pacing/SKILL.md"
        )
        let text = """
            ---
            name: Cut Pacing
            description: Tighten dialogue pacing.
            ---

            ## Workflow
            1. Review the cut.
            """

        let preview = SkillCatalog.preview(for: entry, text: text)

        #expect(preview.name == "Cut Pacing")
        #expect(preview.description == "Tighten dialogue pacing.")
        #expect(preview.body.contains("Review the cut."))
    }

    @Test func fallsBackToCatalogMetadataWithoutRequiredFrontmatter() {
        let entry = SkillCatalogEntry(
            id: "color-pass",
            name: "Color Pass",
            description: "Balance exposure and color.",
            sha: "def456",
            path: "skills/color-pass/SKILL.md"
        )
        let text = """
            ---
            name: 
            description: 
            ---

            Use a soft grade first.
            """

        let preview = SkillCatalog.preview(for: entry, text: text)

        #expect(preview.name == "Color Pass")
        #expect(preview.description == "Balance exposure and color.")
        #expect(preview.body == "Use a soft grade first.")
    }
}
