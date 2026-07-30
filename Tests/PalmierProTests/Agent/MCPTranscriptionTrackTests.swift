import MCP
import Testing
@testable import PalmierPro

@Suite("MCP transcription track selection", .serialized)
@MainActor
struct MCPTranscriptionTrackTests {
    @Test func discoveryAndTrackValidationCrossMCPBoundary() async throws {
        let clip = Fixtures.clip(id: "voice", mediaType: .audio, start: 0, duration: 30)
        let harness = ToolHarness(timeline: Fixtures.timeline(tracks: [
            Fixtures.audioTrack(id: "voice-track", clips: [clip]),
        ]))
        let server = Server(
            name: "transcription-track-test",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await MCPService.registerTools(on: server, executor: harness.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "transcription-track-test", version: "1.0.0")

        try await server.start(transport: transports.server)
        do {
            _ = try await client.connect(transport: transports.client)
            let (tools, _) = try await client.listTools()
            for name in ["get_transcript", "add_captions"] {
                let tool = try #require(tools.first { $0.name == name })
                let properties = try #require(tool.inputSchema.objectValue?["properties"]?.objectValue)
                #expect(properties["trackIndex"]?.objectValue?["type"]?.stringValue == "integer")
            }

            let transcript = try await client.callTool(
                name: "get_transcript",
                arguments: ["trackIndex": .int(0)]
            )
            #expect(transcript.isError != true)

            for name in ["get_transcript", "add_captions"] {
                let invalid = try await client.callTool(
                    name: name,
                    arguments: ["trackIndex": .int(4)]
                )
                #expect(invalid.isError == true)
            }
        } catch {
            await server.stop()
            await client.disconnect()
            throw error
        }
        await server.stop()
        await client.disconnect()
    }
}
