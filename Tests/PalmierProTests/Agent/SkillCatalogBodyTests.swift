import Foundation
import Testing
@testable import PalmierPro

@Suite("Skill catalog body")
struct SkillCatalogBodyTests {
    @Test func fetchBodyStripsFrontmatterFromLocalFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("palmier-skills-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let markdown = """
            ---
            name: Demo Skill
            description: Preview before install.
            ---

            ## Steps
            1. Read the skill.
            2. Install when ready.
            """
        let url = root.appendingPathComponent("SKILL.md")
        try markdown.write(to: url, atomically: true, encoding: .utf8)

        let body = try await SkillCatalog.fetchBody(from: url)
        #expect(body.contains("## Steps"))
        #expect(body.contains("Install when ready."))
        #expect(!body.contains("name: Demo Skill"))
        #expect(!body.hasPrefix("---"))
    }

    @Test func fetchBodyRejectsMissingFile() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palmier-skills-missing-\(UUID().uuidString).md")
        await #expect(throws: (any Error).self) {
            _ = try await SkillCatalog.fetchBody(from: url)
        }
    }

    @Test func fetchBodyRejectsNilURL() async {
        await #expect(throws: URLError.self) {
            _ = try await SkillCatalog.fetchBody(from: nil)
        }
    }

    @Test func fetchBodyRejectsMissingRequiredFrontmatter() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("palmier-skills-invalid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let markdown = """
            ---
            description: Missing name field.
            ---

            Body text that must not preview.
            """
        let url = root.appendingPathComponent("SKILL.md")
        try markdown.write(to: url, atomically: true, encoding: .utf8)

        await #expect(throws: URLError.self) {
            _ = try await SkillCatalog.fetchBody(from: url)
        }
    }
}
