import Foundation
import Observation
import WatchKit
import RefAppWatchCore

@MainActor @Observable
final class LiveMatchModel {
    private(set) var events: [MatchEvent] = []
    private(set) var errorMessage: String?
    let matchID = LiveMatchModel.persistentUUID(forKey: "refapp.watch.active-match-id")
    let deviceID = LiveMatchModel.persistentDeviceID()
    let format: MatchFormat = .regulation

    private let store: EventStore

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        store = EventStore(fileURL: base.appendingPathComponent("active-match-events.json"))
        Task { await restore() }
    }

    func clock(at date: Date) -> MatchClockState { MatchEngine.clock(from: events, format: format, now: date) }
    var score: MatchScore { MatchEngine.score(from: events) }

    func toggleClock(at date: Date) {
        let clock = clock(at: date)
        guard !clock.isFinished, clock.period != .halfTime, clock.period != .extraTimeBreak else { return }
        let payload: MatchEventPayload
        if events.isEmpty { payload = .periodStarted(.firstHalf) }
        else { payload = clock.isRunning ? .clockPaused(reason: nil) : .clockResumed }
        append(payload, at: date)
    }

    func addGoal(side: MatchSide, at date: Date) { append(.goal(side: side, scorer: nil), at: date) }

    func addCard(_ card: CardKind, side: MatchSide, person: PersonReference, at date: Date) {
        append(.card(card, side: side, person: person, reason: nil), at: date)
    }

    func addSubstitution(side: MatchSide, playerOut: Int, playerIn: Int, at date: Date) {
        append(
            .substitution(
                side: side,
                playerOut: PersonReference(number: playerOut, role: .player),
                playerIn: PersonReference(number: playerIn, role: .player)
            ),
            at: date
        )
    }

    func advancePeriod(at date: Date) {
        let state = clock(at: date)
        let payload: MatchEventPayload
        switch state.period {
        case .firstHalf: payload = .periodEnded(.firstHalf)
        case .halfTime: payload = .periodStarted(.secondHalf)
        case .secondHalf: payload = .periodEnded(.secondHalf)
        case .extraTimeFirst: payload = .periodEnded(.extraTimeFirst)
        case .extraTimeBreak: payload = .periodStarted(.extraTimeSecond)
        case .extraTimeSecond: payload = .periodEnded(.extraTimeSecond)
        case .penalties: payload = .periodEnded(.penalties)
        }
        append(payload, at: date)
    }

    func periodActionLabel(at date: Date) -> String {
        let state = clock(at: date)
        return switch state.period {
        case .firstHalf: "İlk yarıyı bitir"
        case .halfTime: "İkinci yarıyı başlat"
        case .secondHalf: format == .regulation ? "Maçı bitir" : "Normal süreyi bitir"
        case .extraTimeFirst: "Uzatma ilk devreyi bitir"
        case .extraTimeBreak: "Uzatma ikinci devreyi başlat"
        case .extraTimeSecond: format == .penalties ? "Penaltılara geç" : "Maçı bitir"
        case .penalties: "Maçı bitir"
        }
    }

    func undoLast(at date: Date) {
        guard let target = MatchEngine.activeEvents(events).last(where: { event in
            switch event.payload { case .goal, .card, .substitution: true; default: false }
        }) else { return }
        append(.eventRetracted(targetID: target.id), at: date)
    }

    private func append(_ payload: MatchEventPayload, at date: Date) {
        let event = MatchEvent(matchID: matchID, occurredAt: date, deviceID: deviceID, payload: payload)
        Task {
            do {
                events = try await store.append(event)
                WKInterfaceDevice.current().play(.success)
            } catch {
                errorMessage = "Kayıt yapılamadı"
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    private func restore() async {
        do { events = try await store.load() }
        catch { errorMessage = "Maç kaydı açılamadı" }
    }

    private static func persistentDeviceID() -> String {
        persistentUUID(forKey: "refapp.watch.device-id").uuidString
    }

    private static func persistentUUID(forKey key: String) -> UUID {
        if let raw = UserDefaults.standard.string(forKey: key), let existing = UUID(uuidString: raw) {
            return existing
        }
        let value = UUID()
        UserDefaults.standard.set(value.uuidString, forKey: key)
        return value
    }
}
