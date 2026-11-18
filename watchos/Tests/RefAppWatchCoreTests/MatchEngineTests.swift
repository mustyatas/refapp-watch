import Foundation
import Testing
@testable import RefAppWatchCore

private let matchID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let deviceID = "watch-ultra-2"
private let kickoff = Date(timeIntervalSince1970: 1_700_000_000)

private func event(_ payload: MatchEventPayload, seconds: TimeInterval, id: UUID = UUID()) -> MatchEvent {
    MatchEvent(id: id, matchID: matchID, occurredAt: kickoff.addingTimeInterval(seconds), deviceID: deviceID, payload: payload)
}

@Test func completedPeriodsSnapToOfficialBoundaryInDemoMode() {
    let halfTime = MatchEngine.clock(from: [
        event(.periodStarted(.firstHalf), seconds: 0),
        event(.periodEnded(.firstHalf), seconds: 5),
    ], format: .regulation, now: kickoff.addingTimeInterval(5))
    #expect(halfTime.displayTime == 45 * 60)

    let fullTime = MatchEngine.clock(from: [
        event(.periodStarted(.firstHalf), seconds: 0),
        event(.periodEnded(.firstHalf), seconds: 5),
        event(.periodStarted(.secondHalf), seconds: 6),
        event(.periodEnded(.secondHalf), seconds: 11),
    ], format: .regulation, now: kickoff.addingTimeInterval(11))
    #expect(fullTime.displayTime == 90 * 60)
    #expect(fullTime.isFinished)
}

@Test func clockSurvivesProcessTermination() {
    let events = [event(.periodStarted(.firstHalf), seconds: 0)]
    let state = MatchEngine.clock(from: events, format: .regulation, now: kickoff.addingTimeInterval(44 * 60))
    #expect(state.isRunning)
    #expect(state.displayTime == 44 * 60)
}

@Test func pauseDoesNotAdvancePlayedTime() {
    let events = [
        event(.periodStarted(.firstHalf), seconds: 0),
        event(.clockPaused(reason: "sakatlık"), seconds: 10 * 60),
    ]
    let state = MatchEngine.clock(from: events, format: .regulation, now: kickoff.addingTimeInterval(15 * 60))
    #expect(!state.isRunning)
    #expect(state.displayTime == 10 * 60)
    #expect(state.stoppage == 5 * 60)
}

@Test func duplicateTransferDoesNotDuplicateGoal() {
    let goalID = UUID()
    let goal = event(.goal(side: .home, scorer: nil), seconds: 10 * 60, id: goalID)
    #expect(MatchEngine.score(from: [goal, goal]) == MatchScore(home: 1, away: 0))
}

@Test func retractingGoalCorrectsScoreWithoutDeletingHistory() {
    let goalID = UUID()
    let goal = event(.goal(side: .away, scorer: nil), seconds: 10 * 60, id: goalID)
    let undo = event(.eventRetracted(targetID: goalID), seconds: 11 * 60)
    #expect(MatchEngine.score(from: [goal, undo]) == MatchScore())
}

@Test func secondHalfStartsAtFortyFiveMinutes() {
    let events = [
        event(.periodStarted(.firstHalf), seconds: 0),
        event(.periodEnded(.firstHalf), seconds: 47 * 60),
        event(.periodStarted(.secondHalf), seconds: 62 * 60),
    ]
    let state = MatchEngine.clock(from: events, format: .regulation, now: kickoff.addingTimeInterval(72 * 60))
    #expect(state.displayTime == 55 * 60)
}

@Test func goalTypeRoundTripsAndOldGoalsStillDecode() throws {
    let encoded = try JSONEncoder().encode(MatchEventPayload.goal(side: .home, scorer: nil, goalType: .header))
    #expect(String(decoding: encoded, as: UTF8.self).contains("\"goalType\":\"header\""))

    let skipped = try JSONEncoder().encode(MatchEventPayload.goal(side: .home, scorer: nil, goalType: nil))
    #expect(!String(decoding: skipped, as: UTF8.self).contains("goalType"))

    let old = try JSONDecoder().decode(MatchEventPayload.self, from: Data(#"{"goal":{"side":"home"}}"#.utf8))
    #expect(old == .goal(side: .home, scorer: nil, goalType: nil))

    let ownGoal = event(.goal(side: .away, scorer: PersonReference(number: 4, role: .player), goalType: .ownGoal), seconds: 60)
    #expect(MatchEngine.score(from: [ownGoal]) == MatchScore(home: 0, away: 1))
}

@Test func shootoutGoalsEncodeInWireShapeAndCountApartFromTheScore() throws {
    let encoded = try JSONEncoder().encode(MatchEventPayload.shootoutGoal(side: .home))
    #expect(String(decoding: encoded, as: UTF8.self) == #"{"shootoutGoal":{"side":"home"}}"#)

    let undoneID = UUID()
    let events = [
        event(.shootoutGoal(side: .home), seconds: 7300),
        event(.shootoutGoal(side: .away), seconds: 7360),
        event(.shootoutGoal(side: .home), seconds: 7420, id: undoneID),
        event(.eventRetracted(targetID: undoneID), seconds: 7430),
    ]
    #expect(MatchEngine.score(from: events) == MatchScore())
    #expect(MatchEngine.shootoutScore(from: events) == MatchScore(home: 1, away: 1))
}

private func running(_ period: MatchPeriod, _ display: TimeInterval, isRunning: Bool = true) -> MatchClockState {
    MatchClockState(period: period, isRunning: isRunning, isFinished: false, elapsedInPeriod: 0, displayTime: display, stoppage: 0)
}

@Test func alertsWarnEndAndCountDownAddedTime() {
    #expect(MatchAlerts.due(running(.firstHalf, 42 * 60 + 59), nil) == nil)
    #expect(MatchAlerts.due(running(.firstHalf, 43 * 60), nil) == .warning)
    #expect(MatchAlerts.due(running(.secondHalf, 90 * 60), nil) == .regularEnd)
    #expect(MatchAlerts.due(running(.firstHalf, 44 * 60, isRunning: false), nil) == nil)
    #expect(MatchAlerts.due(running(.halfTime, 45 * 60), nil) == nil)

    let added = AddedTime(period: .firstHalf, minutes: 3)
    #expect(MatchAlerts.addedRemaining(running(.firstHalf, 45 * 60 + 30), added) == 150)
    #expect(MatchAlerts.due(running(.firstHalf, 47 * 60), added) == .regularEnd)
    #expect(MatchAlerts.due(running(.firstHalf, 48 * 60), added) == .addedTimeUp)
    #expect(MatchAlerts.addedRemaining(running(.secondHalf, 91 * 60), added) == nil)
}
