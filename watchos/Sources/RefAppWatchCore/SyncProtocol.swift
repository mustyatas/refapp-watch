import Foundation

public enum SyncMessageKind: String, Codable, Sendable {
    case eventBatch = "event_batch"
    case acknowledgement
}

public struct EventBatch: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let batchID: UUID
    public let matchID: UUID
    public let senderDeviceID: String
    public let events: [MatchEvent]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        batchID: UUID = UUID(),
        matchID: UUID,
        senderDeviceID: String,
        events: [MatchEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.batchID = batchID
        self.matchID = matchID
        self.senderDeviceID = senderDeviceID
        self.events = events
    }
}

public struct SyncAcknowledgement: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let batchID: UUID
    public let acknowledgedEventIDs: [UUID]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        batchID: UUID,
        acknowledgedEventIDs: [UUID]
    ) {
        self.schemaVersion = schemaVersion
        self.batchID = batchID
        self.acknowledgedEventIDs = acknowledgedEventIDs
    }
}

public enum SyncEngine {
    public static func pendingEvents(
        from events: [MatchEvent],
        acknowledgedEventIDs: Set<UUID>
    ) -> [MatchEvent] {
        events
            .filter { !acknowledgedEventIDs.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.occurredAt == rhs.occurredAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.occurredAt < rhs.occurredAt
            }
    }

    public static func merge(local: [MatchEvent], incoming: [MatchEvent]) -> [MatchEvent] {
        var eventsByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for event in incoming where eventsByID[event.id] == nil {
            eventsByID[event.id] = event
        }
        return eventsByID.values.sorted { lhs, rhs in
            lhs.occurredAt == rhs.occurredAt
                ? lhs.id.uuidString < rhs.id.uuidString
                : lhs.occurredAt < rhs.occurredAt
        }
    }
}
