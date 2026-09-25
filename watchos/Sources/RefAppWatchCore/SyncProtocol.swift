import Foundation

public enum SyncMessageKind: String, Codable, Sendable {
    case eventBatch = "event_batch"
    case acknowledgement
    case matchPackage = "match_package"
}

public struct WatchMatch: Codable, Equatable, Sendable {
    public let id: String
    public let homeTeamName: String
    public let awayTeamName: String
    public let format: MatchFormat
    public let scheduledAt: String
    public let homeColor: String?
    public let awayColor: String?

    public init(
        id: String,
        homeTeamName: String,
        awayTeamName: String,
        format: MatchFormat,
        scheduledAt: String,
        homeColor: String? = nil,
        awayColor: String? = nil
    ) {
        self.id = id
        self.homeTeamName = homeTeamName
        self.awayTeamName = awayTeamName
        self.format = format
        self.scheduledAt = scheduledAt
        self.homeColor = homeColor
        self.awayColor = awayColor
    }
}

public struct WatchRosterPlayer: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let side: MatchSide
    public let name: String
    public let number: Int?
    public let isStarter: Bool

    public init(id: String, side: MatchSide, name: String, number: Int?, isStarter: Bool) {
        self.id = id
        self.side = side
        self.name = name
        self.number = number
        self.isStarter = isStarter
    }
}

public struct WatchStaffMember: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let side: MatchSide
    public let name: String
    public let role: String?
}

public struct WatchMatchPackage: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let match: WatchMatch
    public let roster: [WatchRosterPlayer]
    public let staff: [WatchStaffMember]
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
