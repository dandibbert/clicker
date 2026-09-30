import Foundation

public struct Script: Codable, Equatable, Sendable, Identifiable {
    public static let currentSchemaVersion = 4

    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var blocks: [ActionBlock]
    public var repeatCount: Int
    public var repeatForever: Bool
    public var repeatInterval: TimeInterval
    public var schemaVersion: Int
    public var trailingDelay: TimeInterval
    public var targetBundleIdentifier: String?
    public var playbackShortcut: ScriptShortcut?
    /// Nil for complete recordings; persisted so a partial capture is never mistaken for a complete script.
    public var recordingInterruption: String?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        blocks: [ActionBlock] = [],
        repeatCount: Int = 1,
        repeatForever: Bool = false,
        repeatInterval: TimeInterval = 0,
        schemaVersion _: Int = Script.currentSchemaVersion,
        trailingDelay: TimeInterval = 0,
        targetBundleIdentifier: String? = nil,
        playbackShortcut: ScriptShortcut? = nil,
        recordingInterruption: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.blocks = blocks
        self.repeatCount = repeatCount
        self.repeatForever = repeatForever
        self.repeatInterval = repeatInterval
        schemaVersion = Self.currentSchemaVersion
        self.trailingDelay = trailingDelay
        self.targetBundleIdentifier = targetBundleIdentifier
        self.playbackShortcut = playbackShortcut
        self.recordingInterruption = recordingInterruption
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, modifiedAt, blocks
        case repeatCount, repeatForever, repeatInterval
        case schemaVersion, trailingDelay, targetBundleIdentifier, playbackShortcut, recordingInterruption
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...Self.currentSchemaVersion).contains(decodedVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported script schema version \(decodedVersion)"
            )
        }
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        let decodedBlocks = try container.decode([ActionBlock].self, forKey: .blocks)
        blocks = decodedVersion < Self.currentSchemaVersion
            ? Self.migrateLegacyBlocks(decodedBlocks)
            : decodedBlocks.map { $0.clearingLegacyTiming() }
        repeatCount = try container.decode(Int.self, forKey: .repeatCount)
        repeatForever = try container.decode(Bool.self, forKey: .repeatForever)
        repeatInterval = try container.decode(TimeInterval.self, forKey: .repeatInterval)
        schemaVersion = Self.currentSchemaVersion
        trailingDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .trailingDelay) ?? 0
        targetBundleIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .targetBundleIdentifier
        )
        recordingInterruption = try container.decodeIfPresent(String.self, forKey: .recordingInterruption)
        playbackShortcut = try container.decodeIfPresent(
            ScriptShortcut.self,
            forKey: .playbackShortcut
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(blocks, forKey: .blocks)
        try container.encode(repeatCount, forKey: .repeatCount)
        try container.encode(repeatForever, forKey: .repeatForever)
        try container.encode(repeatInterval, forKey: .repeatInterval)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(trailingDelay, forKey: .trailingDelay)
        try container.encodeIfPresent(targetBundleIdentifier, forKey: .targetBundleIdentifier)
        try container.encodeIfPresent(playbackShortcut, forKey: .playbackShortcut)
        try container.encodeIfPresent(recordingInterruption, forKey: .recordingInterruption)
    }

    private static func migrateLegacyBlocks(_ legacyBlocks: [ActionBlock]) -> [ActionBlock] {
        var clock: TimeInterval = 0
        var nextOrdinal = 0
        return legacyBlocks.map { legacy in
            let start: TimeInterval
            if case .wait = legacy {
                start = clock
                clock = TimelineValue.adding(clock, legacy.effectiveDuration)
            } else {
                clock = TimelineValue.adding(clock, legacy.delayBefore)
                start = max(0, clock - TimelineValue.time(legacy.overlapBefore))
                clock = max(clock, TimelineValue.adding(start, legacy.effectiveDuration))
            }
            return legacy
                .withStartOffset(start)
                .clearingLegacyTiming()
                .assigningLegacyOrdinals(next: &nextOrdinal)
        }
    }
}

public struct ScriptShortcut: Codable, Equatable, Hashable, Sendable {
    public static let supportedModifierMask = KeyCodeMap.maskControl
        | KeyCodeMap.maskOption
        | KeyCodeMap.maskShift
        | KeyCodeMap.maskCommand

    public let keyCode: UInt16
    public let modifierFlags: UInt64

    public init(keyCode: UInt16, modifierFlags: UInt64) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags & Self.supportedModifierMask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt16.self, forKey: .keyCode),
            modifierFlags: try container.decode(UInt64.self, forKey: .modifierFlags)
        )
    }

    public var displayName: String {
        KeyCodeMap.shortcutDisplay(keyCode: keyCode, flags: modifierFlags)
    }
}
