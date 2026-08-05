import Testing
@testable import PalmierPro

@Suite("Recommended skills")
struct RecommendedSkillsTests {
    @Test func includesCaptionTemplates() {
        #expect(RecommendedSkills.contains("caption-templates"))
    }

    @Test func ignoresUnlistedSkills() {
        #expect(!RecommendedSkills.contains("color-grading"))
    }
}
