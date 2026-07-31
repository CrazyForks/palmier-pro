import Foundation

enum BundledResource {
    static let bundle: Bundle = {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return .main }
        return .module
    }()

    static func url(_ path: String) -> URL? {
        let candidates = [
            bundle.resourceURL?.appendingPathComponent(path),
            Bundle.main.resourceURL?.appendingPathComponent(path),
            Bundle.main.resourceURL?.appendingPathComponent("PalmierPro_PalmierPro.bundle/\(path)"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
