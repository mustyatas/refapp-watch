import Foundation

/// The vibrations the live screen gives during a half. Watch-only: not part of the protocol.
public enum MatchAlert: Sendable { case warning, regularEnd, addedTimeUp }

/// The added time the referee announced for one period, in whole minutes.
public struct AddedTime: Codable, Equatable, Sendable {
    public let period: MatchPeriod
    public let minutes: Int

    public init(period: MatchPeriod, minutes: Int) {
        self.period = period
        self.minutes = minutes
    }
}

/// Same rules as the Wear OS core's MatchAlerts and the Garmin Alerts module.
public enum MatchAlerts {
    public static let warningSeconds: TimeInterval = 120
    public static let addedMinutes = Array(1...10)

    /// Seconds on the match clock where the period's regular time ends; nil outside a half.
    public static func regularEnd(_ period: MatchPeriod) -> TimeInterval? {
        switch period {
        case .firstHalf: 45 * 60
        case .secondHalf: 90 * 60
        case .extraTimeFirst: 105 * 60
        case .extraTimeSecond: 120 * 60
        default: nil
        }
    }

    /// The added time when it belongs to the period being played.
    public static func current(_ clock: MatchClockState, _ added: AddedTime?) -> AddedTime? {
        guard let added, added.period == clock.period, !clock.isFinished else { return nil }
        return added
    }

    /// Played seconds of added time left, never below zero; nil when none was set for this period.
    public static func addedRemaining(_ clock: MatchClockState, _ added: AddedTime?) -> TimeInterval? {
        guard let set = current(clock, added), let end = regularEnd(clock.period) else { return nil }
        return max(0, end + TimeInterval(set.minutes * 60) - clock.displayTime)
    }

    /// The alert due at this moment, the latest one first. The caller fires each
    /// (period, alert) once, so an alert that is already past simply stays due.
    public static func due(_ clock: MatchClockState, _ added: AddedTime?) -> MatchAlert? {
        guard clock.isRunning, let end = regularEnd(clock.period) else { return nil }
        if let remaining = addedRemaining(clock, added), remaining <= 0 { return .addedTimeUp }
        if clock.displayTime >= end { return .regularEnd }
        if clock.displayTime >= end - warningSeconds { return .warning }
        return nil
    }
}
