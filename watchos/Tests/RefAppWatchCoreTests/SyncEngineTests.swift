import Foundation
import Testing
@testable import RefAppWatchCore

private let syncMatchID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
private let syncStart = Date(timeIntervalSince1970: 1_700_000_000)

private func syncEvent(id: UUID = UUID(), seconds: TimeInterval) -> MatchEvent {
    MatchEvent(
        id: id,
        matchID: syncMatchID,
        occurredAt: syncStart.addingTimeInterval(seconds),
        deviceID: "watch-ultra-2",
        payload: .note("test")
    )
}

@Test func acknowledgedEventsLeaveTheOutbox() {
    let first = syncEvent(seconds: 1)
    let second = syncEvent(seconds: 2)

    let pending = SyncEngine.pendingEvents(
        from: [first, second],
        acknowledgedEventIDs: [first.id]
    )

    #expect(pending == [second])
}

@Test func mergeIsIdempotentAndKeepsChronologicalOrder() {
    let first = syncEvent(seconds: 1)
    let second = syncEvent(seconds: 2)

    let merged = SyncEngine.merge(local: [second], incoming: [first, second])

    #expect(merged == [first, second])
}

@Test func eventBatchRoundTripsWithoutLosingPayload() throws {
    let goal = MatchEvent(
        matchID: syncMatchID,
        occurredAt: syncStart,
        deviceID: "watch-ultra-2",
        payload: .goal(side: .home, scorer: PersonReference(number: 9, role: .player))
    )
    let batch = EventBatch(matchID: syncMatchID, senderDeviceID: "watch-ultra-2", events: [goal])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970

    let decoded = try decoder.decode(EventBatch.self, from: encoder.encode(batch))

    #expect(decoded == batch)
}

@Test func matchPackageRoundTripsWithRosterAndStaff() throws {
    let package = WatchMatchPackage(
        schemaVersion: 1,
        match: WatchMatch(
            id: syncMatchID.uuidString,
            homeTeamName: "Ev Spor",
            awayTeamName: "Deplasman Spor",
            format: .penalties,
            scheduledAt: "2026-09-22T18:00:00Z"
        ),
        roster: [
            WatchRosterPlayer(
                id: "player-1",
                side: .home,
                name: "Oyuncu Bir",
                number: 9,
                isStarter: true
            ),
        ],
        staff: [
            WatchStaffMember(
                id: "staff-1",
                side: .away,
                name: "Teknik Sorumlu",
                role: "Teknik direktör"
            ),
        ]
    )

    let data = try JSONEncoder().encode(package)
    let decoded = try JSONDecoder().decode(WatchMatchPackage.self, from: data)

    #expect(decoded == package)
}
