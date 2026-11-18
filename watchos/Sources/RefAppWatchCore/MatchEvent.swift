import Foundation

public enum MatchSide: String, Codable, Sendable { case home, away }
public enum PersonRole: String, Codable, Sendable { case player, staff }
public enum MatchPeriod: String, Codable, Sendable { case firstHalf = "1h", halfTime = "ht", secondHalf = "2h", extraTimeFirst = "et1", extraTimeBreak = "et_ht", extraTimeSecond = "et2", penalties = "pens" }
public enum CardKind: String, Codable, Sendable { case yellow, red }
/// How a goal was scored. `nil` on a goal means the referee skipped the choice.
public enum GoalType: String, Codable, CaseIterable, Sendable { case foot, header, penalty, ownGoal = "own_goal" }

public struct PersonReference: Codable, Equatable, Sendable {
    public let number: Int?
    public let name: String?
    public let role: PersonRole

    public init(number: Int? = nil, name: String? = nil, role: PersonRole) {
        self.number = number
        self.name = name
        self.role = role
    }
}

public enum MatchEventPayload: Codable, Equatable, Sendable {
    case periodStarted(MatchPeriod)
    case periodEnded(MatchPeriod)
    case clockPaused(reason: String?)
    case clockResumed
    case card(CardKind, side: MatchSide, person: PersonReference, reason: String?)
    /// `side` is the team that gets the point, also for an own goal.
    case goal(side: MatchSide, scorer: PersonReference?, goalType: GoalType? = nil)
    case substitution(side: MatchSide, playerOut: PersonReference, playerIn: PersonReference)
    case note(String)
    case eventRetracted(targetID: UUID)
}

public struct MatchEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let matchID: UUID
    public let occurredAt: Date
    public let deviceID: String
    public let payload: MatchEventPayload

    public init(id: UUID = UUID(), matchID: UUID, occurredAt: Date, deviceID: String, payload: MatchEventPayload) {
        self.id = id
        self.matchID = matchID
        self.occurredAt = occurredAt
        self.deviceID = deviceID
        self.payload = payload
    }
}
