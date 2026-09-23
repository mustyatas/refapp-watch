import Foundation

public enum MatchFormat: String, Codable, Sendable { case regulation = "90", extraTime = "90+et", penalties = "90+et+p" }

public struct MatchClockState: Equatable, Sendable {
    public let period: MatchPeriod
    public let isRunning: Bool
    public let isFinished: Bool
    public let elapsedInPeriod: TimeInterval
    public let displayTime: TimeInterval
    public let stoppage: TimeInterval
}

public struct MatchScore: Equatable, Sendable {
    public var home = 0
    public var away = 0

    public init(home: Int = 0, away: Int = 0) {
        self.home = home
        self.away = away
    }
}

public enum MatchEngine {
    public static func activeEvents(_ events: [MatchEvent]) -> [MatchEvent] {
        var unique: [UUID: MatchEvent] = [:]
        for event in events where unique[event.id] == nil { unique[event.id] = event }
        let retracted = Set(unique.values.compactMap { event -> UUID? in
            if case .eventRetracted(let targetID) = event.payload { return targetID }
            return nil
        })
        return unique.values
            .filter { event in
                if case .eventRetracted = event.payload { return false }
                return !retracted.contains(event.id)
            }
            .sorted { lhs, rhs in
                lhs.occurredAt == rhs.occurredAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.occurredAt < rhs.occurredAt
            }
    }

    public static func score(from events: [MatchEvent]) -> MatchScore {
        activeEvents(events).reduce(into: MatchScore()) { result, event in
            guard case .goal(let side, _) = event.payload else { return }
            if side == .home { result.home += 1 } else { result.away += 1 }
        }
    }

    public static func clock(from events: [MatchEvent], format: MatchFormat, now: Date) -> MatchClockState {
        var period: MatchPeriod = .firstHalf
        var finished = false
        var startedAt: Date?
        var endedAt: Date?
        var lastEndedPeriod: MatchPeriod?
        var pausedAt: Date?
        var stoppage: TimeInterval = 0

        for event in activeEvents(events) {
            switch event.payload {
            case .periodStarted(let nextPeriod):
                period = nextPeriod; startedAt = event.occurredAt; endedAt = nil; lastEndedPeriod = nil; pausedAt = nil; stoppage = 0
            case .periodEnded(let endedPeriod):
                if let pause = pausedAt { stoppage += max(0, event.occurredAt.timeIntervalSince(pause)); pausedAt = nil }
                endedAt = event.occurredAt
                lastEndedPeriod = endedPeriod
                if let next = nextPeriod(after: endedPeriod, format: format) { period = next } else { finished = true }
            case .clockPaused:
                if startedAt != nil, endedAt == nil, pausedAt == nil { pausedAt = event.occurredAt }
            case .clockResumed:
                if let pause = pausedAt { stoppage += max(0, event.occurredAt.timeIntervalSince(pause)); pausedAt = nil }
            default: break
            }
        }

        let offset = periodOffset(period)
        guard let start = startedAt else { return .init(period: period, isRunning: false, isFinished: finished, elapsedInPeriod: 0, displayTime: offset, stoppage: stoppage) }
        if let endedAt, let endedPeriod = lastEndedPeriod {
            let elapsed = max(0, endedAt.timeIntervalSince(start) - stoppage)
            let displayTime = max(periodOffset(endedPeriod) + elapsed, periodBoundary(endedPeriod))
            return .init(period: period, isRunning: false, isFinished: finished, elapsedInPeriod: elapsed, displayTime: displayTime, stoppage: stoppage)
        }
        let openPause = pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        let totalStoppage = stoppage + openPause
        let elapsed = max(0, now.timeIntervalSince(start) - totalStoppage)
        return .init(period: period, isRunning: pausedAt == nil, isFinished: finished, elapsedInPeriod: elapsed, displayTime: offset + elapsed, stoppage: totalStoppage)
    }

    private static func periodOffset(_ period: MatchPeriod) -> TimeInterval {
        switch period {
        case .firstHalf, .halfTime: 0
        case .secondHalf: 45 * 60
        case .extraTimeFirst, .extraTimeBreak: 90 * 60
        case .extraTimeSecond: 105 * 60
        case .penalties: 120 * 60
        }
    }

    private static func periodBoundary(_ period: MatchPeriod) -> TimeInterval {
        switch period {
        case .firstHalf, .halfTime: 45 * 60
        case .secondHalf: 90 * 60
        case .extraTimeFirst, .extraTimeBreak: 105 * 60
        case .extraTimeSecond, .penalties: 120 * 60
        }
    }

    private static func nextPeriod(after period: MatchPeriod, format: MatchFormat) -> MatchPeriod? {
        switch period {
        case .firstHalf: .halfTime
        case .halfTime: .secondHalf
        case .secondHalf: format == .regulation ? nil : .extraTimeFirst
        case .extraTimeFirst: .extraTimeBreak
        case .extraTimeBreak: .extraTimeSecond
        case .extraTimeSecond: format == .penalties ? .penalties : nil
        case .penalties: nil
        }
    }
}
