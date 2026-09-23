import Foundation
import Observation
import WatchKit
import RefAppWatchCore

@MainActor @Observable
final class LiveMatchModel {
    private(set) var events: [MatchEvent] = []
    private(set) var errorMessage: String?
    private(set) var pendingSyncCount = 0
    private(set) var matchPackage: WatchMatchPackage?
    private(set) var matchID = LiveMatchModel.persistentUUID(forKey: "refapp.watch.active-match-id")
    let deviceID = LiveMatchModel.persistentDeviceID()
    private(set) var format: MatchFormat = .regulation
    let workout = WorkoutTrackingManager()

    private let store: EventStore
    private let syncCoordinator: WatchSyncCoordinator

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        store = EventStore(fileURL: base.appendingPathComponent("active-match-events.json"))
        syncCoordinator = WatchSyncCoordinator()
        syncCoordinator.configure(
            eventProvider: { [weak self] in self?.events ?? [] },
            incomingEventsHandler: { [weak self] incoming in self?.mergeIncoming(incoming) },
            matchPackageHandler: { [weak self] package in self?.acceptMatchPackage(package) },
            statusHandler: { [weak self] count in self?.pendingSyncCount = count }
        )
        syncCoordinator.start()
        restoreMatchPackage()
        Task { await restore() }
    }

    private var alertedBoundaries: Set<MatchPeriod> = []

    func clock(at date: Date) -> MatchClockState { MatchEngine.clock(from: events, format: format, now: date) }
    var score: MatchScore { MatchEngine.score(from: events) }

    func checkBoundaryAlert(for clock: MatchClockState) {
        guard clock.isRunning else { return }
        let boundary: TimeInterval? = switch clock.period {
        case .firstHalf: 45 * 60
        case .secondHalf: 90 * 60
        case .extraTimeFirst: 105 * 60
        case .extraTimeSecond: 120 * 60
        default: nil
        }
        guard let boundary, clock.displayTime >= boundary, !alertedBoundaries.contains(clock.period) else { return }
        alertedBoundaries.insert(clock.period)
        WKInterfaceDevice.current().play(.notification)
    }

    func teamLabel(_ side: MatchSide) -> String {
        let name = side == .home
            ? matchPackage?.match.homeTeamName
            : matchPackage?.match.awayTeamName
        return name?.isEmpty == false ? String(name!.prefix(8)).uppercased() : side == .home ? "EV" : "DEP"
    }

    func teamColor(_ side: MatchSide) -> String? {
        side == .home ? matchPackage?.match.homeColor : matchPackage?.match.awayColor
    }

    func playerNumbers(for side: MatchSide) -> [Int] {
        let numbers = matchPackage?.roster
            .filter { $0.side == side }
            .compactMap(\.number) ?? []
        return numbers.isEmpty ? Array(1...99) : Array(Set(numbers)).sorted()
    }

    func rosterPlayers(for side: MatchSide) -> [WatchRosterPlayer] {
        matchPackage?.roster
            .filter { $0.side == side }
            .sorted { ($0.number ?? 999, $0.name) < ($1.number ?? 999, $1.name) } ?? []
    }

    func staffMembers(for side: MatchSide) -> [WatchStaffMember] {
        matchPackage?.staff.filter { $0.side == side } ?? []
    }

    func toggleClock(at date: Date) {
        let clock = clock(at: date)
        guard !clock.isFinished, clock.period != .halfTime, clock.period != .extraTimeBreak else { return }
        let payload: MatchEventPayload
        if events.isEmpty {
            payload = .periodStarted(.firstHalf)
            Task { await workout.start(at: date) }
        }
        else { payload = clock.isRunning ? .clockPaused(reason: nil) : .clockResumed }
        append(payload, at: date)
    }

    func startMatch(kickoffSide: MatchSide, at date: Date) {
        guard events.isEmpty else { return }
        let start = MatchEvent(matchID: matchID, occurredAt: date, deviceID: deviceID, payload: .periodStarted(.firstHalf))
        let kickoff = MatchEvent(matchID: matchID, occurredAt: date.addingTimeInterval(0.001), deviceID: deviceID, payload: .note("kickoff:\(kickoffSide.rawValue)"))
        Task {
            do {
                events = try await store.merge([start, kickoff])
                syncCoordinator.eventsDidChange()
                await workout.start(at: date)
                WKInterfaceDevice.current().play(.success)
            } catch {
                errorMessage = "Maç başlatılamadı"
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    var kickoffSide: MatchSide? {
        MatchEngine.activeEvents(events).compactMap { event -> MatchSide? in
            guard case .note(let value) = event.payload, value.hasPrefix("kickoff:") else { return nil }
            return MatchSide(rawValue: String(value.dropFirst("kickoff:".count)))
        }.first
    }

    func addGoal(side: MatchSide, scorer: PersonReference?, at date: Date) {
        append(.goal(side: side, scorer: scorer), at: date)
    }

    func yellowCardCount(side: MatchSide, person: PersonReference) -> Int {
        MatchEngine.activeEvents(events).filter { event in
            guard case .card(.yellow, let eventSide, let eventPerson, _) = event.payload else { return false }
            guard eventSide == side, eventPerson.role == person.role else { return false }
            if let number = person.number { return eventPerson.number == number }
            return eventPerson.name == person.name
        }.count
    }

    func eventClock(_ event: MatchEvent) -> MatchClockState {
        MatchEngine.clock(
            from: events.filter { $0.occurredAt <= event.occurredAt },
            format: format,
            now: event.occurredAt
        )
    }

    func addCard(_ card: CardKind, side: MatchSide, person: PersonReference, reason: String? = nil, at date: Date) {
        append(.card(card, side: side, person: person, reason: reason), at: date)
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

    func addSubstitution(
        side: MatchSide,
        playerOut: WatchRosterPlayer,
        playerIn: WatchRosterPlayer,
        at date: Date
    ) {
        append(
            .substitution(
                side: side,
                playerOut: PersonReference(number: playerOut.number, name: playerOut.name, role: .player),
                playerIn: PersonReference(number: playerIn.number, name: playerIn.name, role: .player)
            ),
            at: date
        )
    }

    func addSubstitution(
        side: MatchSide,
        playerOut: PersonReference,
        playerIn: PersonReference,
        at date: Date
    ) {
        append(.substitution(side: side, playerOut: playerOut, playerIn: playerIn), at: date)
    }

    func advancePeriod(at date: Date) {
        let state = clock(at: date)
        let payload: MatchEventPayload
        switch state.period {
        case .firstHalf: payload = .periodEnded(.firstHalf); workout.pause()
        case .halfTime: payload = .periodStarted(.secondHalf); workout.resume()
        case .secondHalf:
            payload = .periodEnded(.secondHalf)
            if format == .regulation { Task { await workout.finish(at: date) } } else { workout.pause() }
        case .extraTimeFirst: payload = .periodEnded(.extraTimeFirst); workout.pause()
        case .extraTimeBreak: payload = .periodStarted(.extraTimeSecond); workout.resume()
        case .extraTimeSecond:
            payload = .periodEnded(.extraTimeSecond)
            if format == .penalties { workout.pause() } else { Task { await workout.finish(at: date) } }
        case .penalties: payload = .periodEnded(.penalties); Task { await workout.finish(at: date) }
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

    func resumeMatch(at date: Date = Date()) {
        guard let lastEnd = MatchEngine.activeEvents(events).last(where: { event in
            if case .periodEnded = event.payload { return true }
            return false
        }) else { return }
        append(.eventRetracted(targetID: lastEnd.id), at: date)
        workout.resume()
    }

    func finishMatch(at date: Date = Date()) {
        let state = clock(at: date)
        guard !state.isFinished else { return }

        var newEvents = events
        if state.period == .firstHalf {
            newEvents.append(MatchEvent(matchID: matchID, occurredAt: date, deviceID: deviceID, payload: .periodEnded(.firstHalf)))
            newEvents.append(MatchEvent(matchID: matchID, occurredAt: date, deviceID: deviceID, payload: .periodStarted(.secondHalf)))
        } else if state.period == .halfTime {
            newEvents.append(MatchEvent(matchID: matchID, occurredAt: date, deviceID: deviceID, payload: .periodStarted(.secondHalf)))
        }

        let finalPeriod: MatchPeriod = switch format {
        case .regulation: .secondHalf
        case .extraTime: .extraTimeSecond
        case .penalties: .penalties
        }
        newEvents.append(MatchEvent(matchID: matchID, occurredAt: date, deviceID: deviceID, payload: .periodEnded(finalPeriod)))

        Task {
            do {
                events = try await store.replace(with: newEvents)
                syncCoordinator.eventsDidChange()
                await workout.finish(at: date)
                WKInterfaceDevice.current().play(.success)
            } catch {
                errorMessage = "Maç sonlandırılamadı"
            }
        }
    }

    func restartMatch() {
        Task {
            do {
                events = try await store.replace(with: [])
                syncCoordinator.eventsDidChange()
                WKInterfaceDevice.current().play(.success)
            } catch {
                errorMessage = "Maç sıfırlanamadı"
            }
        }
    }

    private func append(_ payload: MatchEventPayload, at date: Date) {
        let event = MatchEvent(matchID: matchID, occurredAt: date, deviceID: deviceID, payload: payload)
        Task {
            do {
                events = try await store.append(event)
                syncCoordinator.eventsDidChange()
                WKInterfaceDevice.current().play(.success)
            } catch {
                errorMessage = "Kayıt yapılamadı"
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    private func restore() async {
        do {
            events = try await store.load()
            syncCoordinator.eventsDidChange()
        }
        catch { errorMessage = "Maç kaydı açılamadı" }
    }

    private func mergeIncoming(_ incoming: [MatchEvent]) {
        Task {
            do {
                events = try await store.merge(incoming)
                syncCoordinator.eventsDidChange()
            } catch {
                errorMessage = "Eşitleme kaydı açılamadı"
            }
        }
    }

    private func acceptMatchPackage(_ package: WatchMatchPackage) {
        let incomingMatchID = UUID(uuidString: package.match.id)
        let isNewMatch = incomingMatchID != nil && incomingMatchID != matchID
        matchPackage = package
        format = package.match.format
        if let incomingMatchID {
            matchID = incomingMatchID
            UserDefaults.standard.set(incomingMatchID.uuidString, forKey: "refapp.watch.active-match-id")
        }
        if let data = try? JSONEncoder().encode(package) {
            UserDefaults.standard.set(data, forKey: "refapp.watch.active-match-package")
        }
        guard isNewMatch else { return }
        alertedBoundaries.removeAll()
        Task {
            do {
                events = try await store.replace(with: [])
                syncCoordinator.eventsDidChange()
                WKInterfaceDevice.current().play(.success)
            } catch {
                errorMessage = "Yeni maç açılamadı"
            }
        }
    }

    private func restoreMatchPackage() {
        guard let data = UserDefaults.standard.data(forKey: "refapp.watch.active-match-package"),
              let package = try? JSONDecoder().decode(WatchMatchPackage.self, from: data) else { return }
        matchPackage = package
        format = package.match.format
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
