import Foundation
import CryptoKit

/// One entry in the published catalog.json. `sha` is a content hash of the SKILL.md
/// and is the version anchor: a changed sha means an update is available.
struct SkillCatalogEntry: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let sha: String
    let path: String

    var version: SkillCatalogVersion {
        SkillCatalogVersion(path: path, sha: sha)
    }
}

struct SkillCatalogVersion: Hashable, Sendable {
    let path: String
    let sha: String
}

struct SkillCatalogDocument: Sendable {
    let version: SkillCatalogVersion
    let data: Data
    let body: String

    func matches(_ entry: SkillCatalogEntry) -> Bool {
        version == entry.version
    }
}

/// Fetches the community skill catalog from the palmier-skills repo (raw GitHub CDN)
@Observable
@MainActor
final class SkillCatalog {
    static let shared = SkillCatalog()

    /// Catalog source. Override with the PALMIER_SKILLS_BASE env var to test against a
    /// local clone, e.g. file:///path/to/palmier-skills.
    static var base: String {
        ProcessInfo.processInfo.environment["PALMIER_SKILLS_BASE"]
            ?? "https://raw.githubusercontent.com/palmier-io/palmier-skills/main"
    }

    private(set) var entries: [SkillCatalogEntry] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    private static var cacheURL: URL {
        DiskCache.rootDirectory.appendingPathComponent("skills-catalog.json")
    }

    private init() { loadCache() }

    func entry(id: String) -> SkillCatalogEntry? { entries.first { $0.id == id } }

    static func bodyURL(path: String) -> URL? { URL(string: "\(base)/\(path)") }

    static func fetchDocument(for entry: SkillCatalogEntry) async throws -> SkillCatalogDocument {
        try await fetchDocument(from: bodyURL(path: entry.path), entry: entry)
    }

    static func fetchDocument(
        from url: URL?,
        entry: SkillCatalogEntry
    ) async throws -> SkillCatalogDocument {
        guard let url else { throw URLError(.badURL) }
        let data = try await fetch(url)
        guard contentSHA(data) == entry.sha else {
            throw URLError(.cannotParseResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        guard let parsed = SkillFrontmatter.requiredFields(text) else {
            throw URLError(.cannotParseResponse)
        }
        return SkillCatalogDocument(
            version: entry.version,
            data: data,
            body: parsed.body
        )
    }

    nonisolated static func contentSHA(_ data: Data) -> String {
        String(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(12))
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let decoded = try? JSONDecoder().decode([SkillCatalogEntry].self, from: data)
        else { return }
        entries = decoded
    }

    func refresh() async {
        guard !isLoading, let url = URL(string: "\(Self.base)/catalog.json") else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await Self.fetch(url)
            entries = try JSONDecoder().decode([SkillCatalogEntry].self, from: data)
            lastError = nil
            try? FileManager.default.createDirectory(
                at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: Self.cacheURL)
            Log.agent.notice("skill catalog loaded \(self.entries.count) entries from \(Self.base)")
        } catch {
            lastError = error.localizedDescription
            Log.agent.error("skill catalog refresh failed (\(Self.base)): \(error.localizedDescription)")
        }
    }

    /// Reads a catalog/body URL. File URLs are read directly
    static func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
