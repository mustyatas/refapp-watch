import Foundation
@preconcurrency import WatchConnectivity
import RefAppWatchCore

@MainActor
final class WatchSyncCoordinator: NSObject, @preconcurrency WCSessionDelegate {
    private enum Key {
        static let kind = "kind"
        static let payload = "payload"
        static let acknowledgedIDs = "refapp.watch.acknowledged-event-ids"
    }

    private let session: WCSession?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var eventProvider: () -> [MatchEvent] = { [] }
    private var incomingEventsHandler: ([MatchEvent]) -> Void = { _ in }
    private var matchPackageHandler: (WatchMatchPackage) -> Void = { _ in }
    private var statusHandler: (Int) -> Void = { _ in }
    private var lastQueuedFingerprint: String?

    override init() {
        session = WCSession.isSupported() ? .default : nil
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
        super.init()
    }

    func configure(
        eventProvider: @escaping () -> [MatchEvent],
        incomingEventsHandler: @escaping ([MatchEvent]) -> Void,
        matchPackageHandler: @escaping (WatchMatchPackage) -> Void,
        statusHandler: @escaping (Int) -> Void
    ) {
        self.eventProvider = eventProvider
        self.incomingEventsHandler = incomingEventsHandler
        self.matchPackageHandler = matchPackageHandler
        self.statusHandler = statusHandler
    }

    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        updatePendingCount()
    }

    func eventsDidChange(force: Bool = false) {
        if force { lastQueuedFingerprint = nil }
        updatePendingCount()
        flushPendingEvents()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard activationState == .activated, error == nil else { return }
            self?.flushPendingEvents()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let kind = userInfo[Key.kind] as? String,
              let payload = userInfo[Key.payload] as? Data else { return }
        Task { @MainActor [weak self] in
            self?.receive(kind: kind, payload: payload)
        }
    }

    private func flushPendingEvents() {
        guard let session, session.activationState == .activated else { return }
        let acknowledged = acknowledgedEventIDs()
        let localEvents = eventProvider().filter { $0.deviceID == deviceID }
        let pending = SyncEngine.pendingEvents(from: localEvents, acknowledgedEventIDs: acknowledged)
        guard !pending.isEmpty else { return }

        let fingerprint = pending.map(\.id.uuidString).joined(separator: ",")
        guard fingerprint != lastQueuedFingerprint,
              let matchID = pending.first?.matchID else { return }

        let batch = EventBatch(
            matchID: matchID,
            senderDeviceID: deviceID,
            events: pending
        )
        guard let data = try? encoder.encode(batch) else { return }

        session.transferUserInfo([
            Key.kind: SyncMessageKind.eventBatch.rawValue,
            Key.payload: data,
        ])
        lastQueuedFingerprint = fingerprint
    }

    private func receive(kind: String, payload: Data) {
        switch SyncMessageKind(rawValue: kind) {
        case .acknowledgement:
            guard let acknowledgement = try? decoder.decode(SyncAcknowledgement.self, from: payload),
                  acknowledgement.schemaVersion == SyncAcknowledgement.currentSchemaVersion else { return }
            var acknowledged = acknowledgedEventIDs()
            acknowledged.formUnion(acknowledgement.acknowledgedEventIDs)
            saveAcknowledgedEventIDs(acknowledged)
            lastQueuedFingerprint = nil
            updatePendingCount()
            flushPendingEvents()

        case .eventBatch:
            guard let batch = try? decoder.decode(EventBatch.self, from: payload),
                  batch.schemaVersion == EventBatch.currentSchemaVersion else { return }
            incomingEventsHandler(batch.events)
            sendAcknowledgement(for: batch)

        case .matchPackage:
            guard let package = try? decoder.decode(WatchMatchPackage.self, from: payload),
                  package.schemaVersion == WatchMatchPackage.currentSchemaVersion else { return }
            matchPackageHandler(package)

        case nil:
            return
        }
    }

    private func sendAcknowledgement(for batch: EventBatch) {
        guard let session, session.activationState == .activated else { return }
        let acknowledgement = SyncAcknowledgement(
            batchID: batch.batchID,
            acknowledgedEventIDs: batch.events.map(\.id)
        )
        guard let data = try? encoder.encode(acknowledgement) else { return }
        session.transferUserInfo([
            Key.kind: SyncMessageKind.acknowledgement.rawValue,
            Key.payload: data,
        ])
    }

    private func updatePendingCount() {
        let localEvents = eventProvider().filter { $0.deviceID == deviceID }
        statusHandler(
            SyncEngine.pendingEvents(
                from: localEvents,
                acknowledgedEventIDs: acknowledgedEventIDs()
            ).count
        )
    }

    private var deviceID: String {
        UserDefaults.standard.string(forKey: "refapp.watch.device-id") ?? "unknown-watch"
    }

    private func acknowledgedEventIDs() -> Set<UUID> {
        let values = UserDefaults.standard.stringArray(forKey: Key.acknowledgedIDs) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    private func saveAcknowledgedEventIDs(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString).sorted(), forKey: Key.acknowledgedIDs)
    }
}
