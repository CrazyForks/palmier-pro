import CoreMedia

struct MediaTime: Codable, Sendable, Equatable, Hashable {
    var value: Int64
    var timescale: Int32
    init(value: Int64, timescale: Int32) { self.value = value; self.timescale = max(1, timescale) }
    init(_ time: CMTime) { self.init(value: time.value, timescale: time.timescale) }
    var cmTime: CMTime { CMTime(value: value, timescale: timescale) }
}

struct MediaTimeRange: Codable, Sendable, Equatable, Hashable {
    var start: MediaTime
    var duration: MediaTime
    init(start: MediaTime, duration: MediaTime) { self.start = start; self.duration = duration }
    init(_ range: CMTimeRange) { self.init(start: MediaTime(range.start), duration: MediaTime(range.duration)) }
    var cmTimeRange: CMTimeRange { CMTimeRange(start: start.cmTime, duration: duration.cmTime) }
}

struct MaskNormalizedPoint: Codable, Sendable, Equatable, Hashable {
    var x, y: Double
}

struct MaskSelection: Codable, Sendable, Equatable {
    var point: MaskNormalizedPoint
    var sourceTime: MediaTime
}

struct ClipMask: Codable, Sendable, Equatable {
    var id: String
    var sourceMediaRef: String
    var sourceRange: MediaTimeRange
    var selection: MaskSelection
    var isApplied: Bool
    var inverted: Bool
    var feather: Double
    var expansion: Double
}
