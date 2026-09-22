import Foundation
import Testing
@testable import RefAppWatchCore

private let matchID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
private let deviceID = "watch-ultra-2"
private let kickoff = Date(timeIntervalSince1970: 1_700_000_000)

private func event(_ payload: MatchEventPayload, seconds: TimeInterval, id: UUID = UUID()) -> MatchEvent {
    MatchEvent(id: id, matchID: matchID, occurredAt: kickoff.addingTimeInterval(seconds), deviceID: deviceID, payload: payload)
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
