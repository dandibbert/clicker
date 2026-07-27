import Foundation

public struct RecordingCapture: Equatable, Sendable {
    public var events: [RecordedEvent]
    public var duration: TimeInterval

    public init(events: [RecordedEvent], duration: TimeInterval) {
        self.events = events
        self.duration = TimelineValue.time(duration)
    }
}

public struct RecordingCutoff: Equatable, Sendable {
    public var eventCount: Int
    public var duration: TimeInterval

    public init(eventCount: Int, duration: TimeInterval) {
        self.eventCount = max(0, eventCount)
        self.duration = TimelineValue.time(duration)
    }
}

public struct GroupedTimeline: Equatable, Sendable {
    public var blocks: [ActionBlock]
    public var trailingDelay: TimeInterval

    public init(blocks: [ActionBlock], trailingDelay: TimeInterval) {
        self.blocks = blocks
        self.trailingDelay = trailingDelay
    }
}
