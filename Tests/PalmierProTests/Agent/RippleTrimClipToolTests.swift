import Foundation
import MCP
import Testing

@testable import PalmierPro

/// c1 sits at [0, 100) with 30 frames of head handle and 50 of tail handle; c2 butts against it.
@MainActor
private func harness() -> ToolHarness {
    ToolHarness(timeline: Fixtures.timeline(tracks: [
        Fixtures.videoTrack(clips: [
            Fixtures.clip(id: "c1", start: 0, duration: 100, trimStart: 30, trimEnd: 50),
            Fixtures.clip(id: "c2", start: 100, duration: 50),
        ]),
    ]))
}

@MainActor
private func spans(_ h: ToolHarness) -> [[Int]] {
    h.editor.timeline.tracks[0].clips
        .sorted { $0.startFrame < $1.startFrame }
        .map { [$0.startFrame, $0.endFrame] }
}

@Suite("ToolExecutor — ripple_trim_clip")
@MainActor
struct RippleTrimClipToolTests {

    @Test func tailDeltaExtendsAndPushesDownstream() async throws {
        let h = harness()
        let json = try #require(await h.runOK("ripple_trim_clip", args: [
            "clipId": "c1", "edge": "tail", "deltaFrames": 20,
        ]) as? [String: Any])
        #expect(json["changed"] as? Bool == true)
        #expect(json["requestedDeltaFrames"] as? Int == 20)
        #expect(json["appliedDeltaFrames"] as? Int == 20)
        #expect(spans(h) == [[0, 120], [120, 170]])
    }

    @Test func tailToFrameLandsTheOutPointOnThatFrame() async throws {
        let h = harness()
        _ = try await h.runOK("ripple_trim_clip", args: ["clipId": "c1", "edge": "tail", "toFrame": 130])
        #expect(spans(h) == [[0, 130], [130, 180]])
        #expect(h.editor.clipFor(id: "c1")?.trimEndFrame == 20)
    }

    @Test func tailShrinkClosesTheGapBehindIt() async throws {
        let h = harness()
        _ = try await h.runOK("ripple_trim_clip", args: ["clipId": "c1", "edge": "tail", "deltaFrames": -30])
        #expect(spans(h) == [[0, 70], [70, 120]])
    }

    @Test func headToFrameKeepsStartAnchoredAndSlidesDownstream() async throws {
        let h = harness()
        _ = try await h.runOK("ripple_trim_clip", args: ["clipId": "c1", "edge": "head", "toFrame": 20])
        #expect(spans(h) == [[0, 80], [80, 130]])
        #expect(h.editor.clipFor(id: "c1")?.trimStartFrame == 50)
    }

    @Test func headDeltaExtendsIntoEarlierSource() async throws {
        let h = harness()
        _ = try await h.runOK("ripple_trim_clip", args: ["clipId": "c1", "edge": "head", "deltaFrames": 30])
        #expect(spans(h) == [[0, 130], [130, 180]])
        #expect(h.editor.clipFor(id: "c1")?.trimStartFrame == 0)
    }

    @Test func edgeAlreadyAtThatFrameIsAReportedNoOp() async throws {
        let h = harness()
        let undoManager = UndoManager()
        h.editor.undo.attach(undoManager)
        let json = try #require(await h.runOK("ripple_trim_clip", args: [
            "clipId": "c1", "edge": "tail", "toFrame": 100,
        ]) as? [String: Any])
        #expect(json["changed"] as? Bool == false)
        #expect(json["appliedDeltaFrames"] as? Int == 0)
        #expect(spans(h) == [[0, 100], [100, 150]])
        #expect(undoManager.canUndo == false)
    }

    @Test func cappedExtendReportsWhatLandedAndWhy() async throws {
        let h = harness()
        let json = try #require(await h.runOK("ripple_trim_clip", args: [
            "clipId": "c1", "edge": "tail", "deltaFrames": 500,
        ]) as? [String: Any])
        #expect(json["requestedDeltaFrames"] as? Int == 500)
        #expect(json["appliedDeltaFrames"] as? Int == 50)
        let notes = json["notes"] as? [String] ?? []
        #expect(notes.contains { $0.contains("Capped at 50") && $0.contains("source media") })
        #expect(spans(h) == [[0, 150], [150, 200]])
    }

    @Test func extendWithNoHandlesFailsAndLeavesTheTimelineAlone() async {
        let h = ToolHarness(timeline: Fixtures.timeline(tracks: [
            Fixtures.videoTrack(clips: [Fixtures.clip(id: "c1", start: 0, duration: 100)]),
        ]))
        let result = await h.runRaw("ripple_trim_clip", args: [
            "clipId": "c1", "edge": "tail", "deltaFrames": 10,
        ])
        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains("no unused source media"))
        #expect(h.editor.clipFor(id: "c1")?.durationFrames == 100)
    }

    @Test func blockedShrinkFailsWithTheSyncLockedObstacle() async {
        // The sync-locked track's clips are already butted at frame 100: no room to slide left.
        let h = ToolHarness(timeline: Fixtures.timeline(tracks: [
            Fixtures.videoTrack(clips: [Fixtures.clip(id: "c1", start: 0, duration: 100)]),
            Fixtures.videoTrack(clips: [
                Fixtures.clip(id: "b0", start: 60, duration: 40),
                Fixtures.clip(id: "b1", start: 100, duration: 50),
            ]),
        ]))
        let result = await h.runRaw("ripple_trim_clip", args: [
            "clipId": "c1", "edge": "tail", "deltaFrames": -20,
        ])
        #expect(result.isError)
        #expect(ToolHarness.textOf(result).contains("frame 100"))
        #expect(h.editor.clipFor(id: "c1")?.durationFrames == 100)
    }

    @Test func linkedAudioTrimsWithTheVideo() async throws {
        var video = Fixtures.clip(id: "v1", start: 0, duration: 100, trimEnd: 50)
        var audio = Fixtures.clip(id: "a1", mediaType: .audio, start: 0, duration: 100, trimEnd: 50)
        video.linkGroupId = "g"
        audio.linkGroupId = "g"
        let h = ToolHarness(timeline: Fixtures.timeline(tracks: [
            Fixtures.videoTrack(clips: [video]),
            Fixtures.audioTrack(clips: [audio]),
        ]))
        _ = try await h.runOK("ripple_trim_clip", args: ["clipId": "v1", "edge": "tail", "deltaFrames": 20])
        #expect(h.editor.clipFor(id: "v1")?.endFrame == 120)
        #expect(h.editor.clipFor(id: "a1")?.endFrame == 120)
    }

    @Test func rejectsMalformedRequests() async {
        let cases: [(label: String, args: [String: Any])] = [
            ("no length given", ["clipId": "c1", "edge": "tail"]),
            ("both lengths given", ["clipId": "c1", "edge": "tail", "deltaFrames": 10, "toFrame": 130]),
            ("unknown edge", ["clipId": "c1", "edge": "middle", "deltaFrames": 10]),
            ("zero delta", ["clipId": "c1", "edge": "tail", "deltaFrames": 0]),
            ("head toFrame past the clip", ["clipId": "c1", "edge": "head", "toFrame": 200]),
            ("tail toFrame before the head", ["clipId": "c1", "edge": "tail", "toFrame": 0]),
            ("overflowing delta", ["clipId": "c1", "edge": "tail", "deltaFrames": Int.min]),
            ("unknown clip", ["clipId": "nope", "edge": "tail", "deltaFrames": 10]),
            ("unknown field", ["clipId": "c1", "edge": "tail", "deltaFrames": 10, "sideways": true]),
        ]
        for (label, args) in cases {
            let h = harness()
            let result = await h.runRaw("ripple_trim_clip", args: args)
            #expect(result.isError, "expected \(label) to be rejected")
            #expect(spans(h) == [[0, 100], [100, 150]], "\(label) must not mutate the timeline")
        }
    }
}

@Suite("MCP ripple_trim_clip")
@MainActor
struct MCPRippleTrimClipTests {

    @Test func discoveryMutationReadbackAndUndo() async throws {
        let h = harness()
        let undoManager = UndoManager()
        h.editor.undo.attach(undoManager)

        let server = Server(
            name: "palmier-pro-test",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await MCPService.registerTools(on: server, executor: h.executor)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "ripple-trim-test", version: "1.0.0")

        try await server.start(transport: transports.server)
        do {
            _ = try await client.connect(transport: transports.client)

            let (tools, _) = try await client.listTools()
            let tool = try #require(tools.first { $0.name == "ripple_trim_clip" })
            let properties = try #require(tool.inputSchema.objectValue?["properties"]?.objectValue)
            let edges = try #require(properties["edge"]?.objectValue?["enum"]?.arrayValue)
            #expect(edges.compactMap(\.stringValue) == ["head", "tail"])
            #expect(properties["deltaFrames"]?.objectValue?["type"]?.stringValue == "integer")
            let required = try #require(tool.inputSchema.objectValue?["required"]?.arrayValue)
            #expect(Set(required.compactMap(\.stringValue)) == ["clipId", "edge"])

            let trim = try await client.callTool(name: "ripple_trim_clip", arguments: [
                "clipId": .string("c1"),
                "edge": .string("tail"),
                "toFrame": .int(130),
            ])
            #expect(trim.isError != true)

            // Read the result back through the protocol rather than trusting the receipt.
            let frames = try await timelineFrames(client: client)
            #expect(frames == [[0, 130], [130, 180]])

            #expect((try await client.callTool(name: "undo")).isError != true)
            let restored = try await timelineFrames(client: client)
            #expect(restored == [[0, 100], [100, 150]])
        } catch {
            await server.stop()
            await client.disconnect()
            throw error
        }
        await server.stop()
        await client.disconnect()
    }

    private func timelineFrames(client: Client) async throws -> [[Int]] {
        let result = try await client.callTool(name: "get_timeline")
        let payload = try #require(
            JSONSerialization.jsonObject(with: Data(text(result.content).utf8)) as? [String: Any]
        )
        let tracks = try #require(payload["tracks"] as? [[String: Any]])
        return tracks
            .flatMap { $0["clips"] as? [[String: Any]] ?? [] }
            .compactMap { $0["frames"] as? [Int] }
            .sorted { ($0.first ?? 0) < ($1.first ?? 0) }
    }

    private func text(_ content: [Tool.Content]) throws -> String {
        for item in content {
            if case .text(let text, _, _) = item { return text }
        }
        throw CocoaError(.coderReadCorrupt)
    }
}
