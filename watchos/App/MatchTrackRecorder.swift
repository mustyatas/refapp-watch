import CoreLocation
import Foundation

/// Records the referee's GPS position for the heat map (protocol section 7 in the
/// referee-mobile repo, docs/watch-protocol/README.md). Fixes become chunks of
/// `chunkSize` points, closed at every period end, kept on disk until the phone
/// acknowledges them and sent as `event_batch` messages with a `track` field.
@MainActor
final class MatchTrackRecorder: NSObject, CLLocationManagerDelegate {
    static let chunkSize = 300
    private static let enabledKey = "refapp.watch.tracking-enabled"

    private let manager = CLLocationManager()
    private let directory: URL
    private var matchID: String?
    private var deviceID = ""
    private var open: [(t: Int64, lat: Double, lon: Double, hr: Int?)] = []
    private var lastTime: Int64?
    private var recording = false
    private var markRequest: (which: String, requestedAt: Date, completion: @MainActor (Double, Double) -> Void)?

    /// Current heart rate, from the workout session.
    var heartRate: @MainActor () -> Double = { 0 }
    /// Hands an encoded batch to the phone link.
    var send: @MainActor (Data) -> Void = { _ in }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("tracks", isDirectory: true)
        super.init()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
    }

    func start(matchID: UUID, deviceID: String) {
        guard isEnabled, !recording else { return }
        if self.matchID != matchID.uuidString { open.removeAll(); lastTime = nil }
        self.matchID = matchID.uuidString
        self.deviceID = deviceID
        recording = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    /// Stops recording and sends what is left (final whistle, app leaving the match).
    func stop() {
        guard recording else { return }
        recording = false
        if markRequest == nil { manager.stopUpdatingLocation() }
        closeChunk()
    }

    /// Marks the centre spot or a corner flag with the first fix after the button press.
    func mark(_ which: String, completion: @escaping @MainActor (Double, Double) -> Void) {
        markRequest = (which, Date(), completion)
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    /// Closes the open chunk (period end) and sends it.
    func closeChunk() {
        guard let matchID, let first = open.first else { return }
        let seqKey = "refapp.watch.track-seq.\(matchID)"
        let seq = max(1, UserDefaults.standard.integer(forKey: seqKey))
        let points: [[Any]] = open.map { point in
            [point.t - first.t, Int64((point.lat * 1e7).rounded()), Int64((point.lon * 1e7).rounded()), point.hr.map { $0 as Any } ?? NSNull()]
        }
        let batchID = UUID().uuidString
        let batch: [String: Any] = [
            "schemaVersion": 1,
            "batchID": batchID,
            "matchID": matchID,
            "senderDeviceID": deviceID,
            "events": [Any](),
            "track": ["seq": seq, "startedAt": first.t, "points": points],
        ]
        open.removeAll()
        UserDefaults.standard.set(seq + 1, forKey: seqKey)
        guard let data = try? JSONSerialization.data(withJSONObject: batch) else { return }
        try? data.write(to: directory.appendingPathComponent("\(batchID).json"), options: .atomic)
        send(data)
    }

    /// Chunks the phone has not acknowledged yet, for a resend.
    func pendingBatches() -> [Data] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? Data(contentsOf: $0) }
    }

    func acknowledge(batchID: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(batchID).json"))
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations
            .filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy < 50 }
            .map { (date: $0.timestamp, lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
        Task { @MainActor in self.receive(fixes) }
    }

    private func receive(_ fixes: [(date: Date, lat: Double, lon: Double)]) {
        for fix in fixes {
            if let request = markRequest, fix.date > request.requestedAt {
                markRequest = nil
                request.completion(fix.lat, fix.lon)
                if !recording { manager.stopUpdatingLocation() }
            }
            guard recording else { continue }
            let t = Int64((fix.date.timeIntervalSince1970 * 1000).rounded())
            if let lastTime, t <= lastTime { continue }
            lastTime = t
            let rate = heartRate()
            open.append((t, fix.lat, fix.lon, rate > 0 ? Int(rate.rounded()) : nil))
            if open.count >= Self.chunkSize { closeChunk() }
        }
    }
}
