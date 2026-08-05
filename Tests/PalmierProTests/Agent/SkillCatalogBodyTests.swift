import Foundation
import Testing
@testable import PalmierPro

@Suite("Skill catalog body")
struct SkillCatalogBodyTests {
    @Test func fetchDocumentStripsFrontmatterFromLocalFile() async throws {
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
        let data = Data(markdown.utf8)

        let document = try await SkillCatalog.fetchDocument(
            from: url,
            entry: entry(path: "skills/demo/SKILL.md", sha: SkillCatalog.contentSHA(data))
        )

        #expect(document.body.contains("## Steps"))
        #expect(document.body.contains("Install when ready."))
        #expect(!document.body.contains("name: Demo Skill"))
        #expect(!document.body.hasPrefix("---"))
    }

    @Test func fetchDocumentRejectsMissingFile() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palmier-skills-missing-\(UUID().uuidString).md")
        await #expect(throws: (any Error).self) {
            _ = try await SkillCatalog.fetchDocument(
                from: url,
                entry: entry(path: "skills/demo/SKILL.md", sha: "missing")
            )
        }
    }

    @Test func fetchDocumentRejectsNilURL() async {
        await #expect(throws: URLError.self) {
            _ = try await SkillCatalog.fetchDocument(
                from: nil,
                entry: entry(path: "skills/demo/SKILL.md", sha: "missing")
            )
        }
    }

    @Test func fetchDocumentRejectsMissingRequiredFrontmatter() async throws {
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
        let data = Data(markdown.utf8)

        await #expect(throws: URLError.self) {
            _ = try await SkillCatalog.fetchDocument(
                from: url,
                entry: entry(path: "skills/demo/SKILL.md", sha: SkillCatalog.contentSHA(data))
            )
        }
    }

    @Test func fetchedDocumentMatchesOnlyItsCatalogVersion() async throws {
        let markdown = """
            ---
            name: Demo Skill
            description: Preview before install.
            ---

            ## Steps
            Read the skill.
            """
        let data = Data(markdown.utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palmier-skills-document-\(UUID().uuidString).md")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let entry = entry(path: "skills/demo/SKILL.md", sha: SkillCatalog.contentSHA(data))

        let document = try await SkillCatalog.fetchDocument(from: url, entry: entry)

        #expect(document.matches(entry))
        #expect(!document.matches(self.entry(path: "skills/demo-v2/SKILL.md", sha: entry.sha)))
        #expect(!document.matches(self.entry(path: entry.path, sha: "new-version")))
        #expect(document.body.contains("Read the skill."))
    }

    @Test func fetchDocumentRejectsContentThatDoesNotMatchCatalogSHA() async throws {
        let markdown = """
            ---
            name: Demo Skill
            description: Preview before install.
            ---

            Body
            """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palmier-skills-mismatch-\(UUID().uuidString).md")
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: URLError.self) {
            _ = try await SkillCatalog.fetchDocument(
                from: url,
                entry: entry(path: "skills/demo/SKILL.md", sha: "stale-sha")
            )
        }
    }

    private func entry(path: String, sha: String) -> SkillCatalogEntry {
        SkillCatalogEntry(
            id: "demo",
            name: "Demo Skill",
            description: "Preview before install.",
            sha: sha,
            path: path
        )
    }
}
