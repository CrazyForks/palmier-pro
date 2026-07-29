import Foundation

extension ToolExecutor {
    func applyMask(_ editor: EditorViewModel, _ raw: [String: Any]) async throws -> ToolResult {
        let args: MaskToolArguments = try decodeToolArgs(raw, path: "apply_mask")
        try args.validate()
        guard let clip = editor.clipFor(id: args.clipId) else {
            throw ToolError("A valid clipId is required")
        }
        guard clip.mediaType == .video else { throw ToolError("apply_mask only supports video clips") }

        switch args.action {
        case "create":
            guard let x = args.pointX, let y = args.pointY else {
                throw ToolError("create requires pointX and pointY")
            }
            let mask = try await editor.generateMask(
                clipId: args.clipId,
                point: MaskNormalizedPoint(x: x, y: y),
                atFrame: args.atFrame,
                isApplied: args.applied ?? true,
                inverted: args.inverted ?? false,
                feather: args.feather ?? 0,
                expansion: args.expansion ?? 0
            )
            return maskReceipt(args.clipId, args.action, mask)

        case "update":
            guard args.pointX == nil, args.pointY == nil, args.atFrame == nil, clip.mask != nil else {
                throw ToolError("update requires an existing mask and does not accept selection arguments")
            }
            guard args.hasControl else { throw ToolError("update requires a mask control") }
            editor.commitClipProperty(clipId: args.clipId, actionName: "Update Mask (Agent)") { clip in
                if let value = args.applied { clip.mask?.isApplied = value }
                if let value = args.inverted { clip.mask?.inverted = value }
                if let value = args.feather { clip.mask?.feather = value }
                if let value = args.expansion { clip.mask?.expansion = value }
            }
            guard let mask = editor.clipFor(id: args.clipId)?.mask else {
                throw ToolError("The mask was not updated")
            }
            return maskReceipt(args.clipId, args.action, mask, changed: mask != clip.mask)

        case "remove":
            guard clip.mask != nil, raw.keys.allSatisfy({ $0 == "clipId" || $0 == "action" }) else {
                throw ToolError("remove requires an existing mask and accepts no controls")
            }
            editor.removeMask(clipId: args.clipId)
            return .ok(Self.jsonString(["clipId": args.clipId, "action": args.action, "masked": false]) ?? "{}")

        default:
            throw ToolError("action must be 'create', 'update', or 'remove'")
        }
    }

    private func maskReceipt(_ clipId: String, _ action: String, _ mask: ClipMask, changed: Bool = true) -> ToolResult {
        .ok(Self.jsonString([
            "clipId": clipId, "action": action, "maskId": mask.id, "masked": true,
            "changed": changed, "applied": mask.isApplied, "inverted": mask.inverted,
            "feather": mask.feather, "expansion": mask.expansion,
        ]) ?? "{}")
    }
}

private struct MaskToolArguments: DecodableToolArgs {
    static let allowedKeys: Set<String> = [
        "clipId", "action", "pointX", "pointY", "atFrame",
        "applied", "inverted", "feather", "expansion",
    ]

    let clipId: String
    let action: String
    var pointX, pointY: Double?
    var atFrame: Int?
    var applied, inverted: Bool?
    var feather, expansion: Double?

    var hasControl: Bool {
        applied != nil || inverted != nil || feather != nil || expansion != nil
    }

    func validate() throws {
        try require(pointX, named: "pointX", in: 0...1)
        try require(pointY, named: "pointY", in: 0...1)
        try require(feather, named: "feather", in: 0...100)
        try require(expansion, named: "expansion", in: -50...50)
    }

    private func require(_ value: Double?, named name: String, in range: ClosedRange<Double>) throws {
        guard let value else { return }
        guard range.contains(value) else {
            throw ToolError("\(name) must be between \(range.lowerBound) and \(range.upperBound)")
        }
    }
}
