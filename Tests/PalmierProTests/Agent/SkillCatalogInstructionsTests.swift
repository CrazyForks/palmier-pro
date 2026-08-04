import Testing
@testable import PalmierPro

@Suite("Skill catalog instructions")
struct SkillCatalogInstructionsTests {
    @Test func stripsFrontmatterFromSkillFile() {
        let text = "---\nname: Cut Pacing\ndescription: Tighten dialogue.\n---\n\n## Workflow\n1. Review the cut."

        #expect(SkillCatalog.instructions(fromSkillFile: text) == "## Workflow\n1. Review the cut.")
    }

    @Test func keepsBodyWhenFrontmatterIsAbsent() {
        #expect(SkillCatalog.instructions(fromSkillFile: "Use a soft grade first.") == "Use a soft grade first.")
    }

    @Test func returnsEmptyInstructionsWhenOnlyFrontmatterExists() {
        #expect(SkillCatalog.instructions(fromSkillFile: "---\nname: A\ndescription: B\n---").isEmpty)
    }
}
