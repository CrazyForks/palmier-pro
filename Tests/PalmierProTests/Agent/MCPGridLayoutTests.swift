import Foundation
import MCP
import Testing
@testable import PalmierPro

@Suite("MCP grid layouts", .serialized)
@MainActor
struct MCPGridLayoutTests {
    @Test func discoveryExposesGridPresetsAndFourByFourTiles() async throws {
        var timeline = Fixtures.timeline()
        timeline.width = 1920
        timeline.height = 1080
        timeline.settingsConfigured = true
        let harness = ToolHarness(timeline: timeline)
        let slotIDs = (1...4).flatMap { row in (1...4).map { "r\(row)c\($0)" } }
        for id in slotIDs {
            let asset = harness.addAsset(id: id, type: .video)
            asset.sourceWidth = 1920
            asset.sourceHeight = 1080
        }

        let server = Server(
            name: "palmier-pro-test",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "grid-layout-test", version: "1.0.0")

        try await server.start(transport: transports.server)
        do {
            _ = try await client.connect(transport: transports.client)

            let (tools, _) = try await client.listTools()
            let tool = try #require(tools.first { $0.name == "apply_layout" })
            let properties = try #require(tool.inputSchema.objectValue?["properties"]?.objectValue)
            let named = properties["layout"]?.objectValue?["enum"]?.arrayValue?.compactMap(\.stringValue)
            #expect(named?.contains("grid_3x3") == true)
            #expect(named?.contains("grid_4x4") == true)

            let apply = try await client.callTool(name: "apply_layout", arguments: [
                "layout": .string("grid_4x4"),
                "endFrame": .int(60),
                "slots": .array(slotIDs.map {
                    .object(["slot": .string($0), "mediaRef": .string($0)])
                }),
            ])
            #expect(apply.isError != true)

            let clips = harness.editor.timeline.tracks.flatMap(\.clips)
            #expect(clips.count == 16)
            #expect(clips.allSatisfy { abs($0.transform.width - 0.25) < 1e-6 })
            #expect(clips.allSatisfy { abs($0.transform.height - 0.25) < 1e-6 })
        } catch {
            await server.stop()
            await client.disconnect()
            throw error
        }
        await server.stop()
        await client.disconnect()
    }
}
