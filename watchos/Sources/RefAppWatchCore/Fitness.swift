import Foundation

/// The training section's pace logic and message, mirroring src/domain/fitness on the phone.
/// docs/watch-protocol/README.md section 8; pinned by vectors/fitness.json.
public enum Fitness {
    public static let cooperSeconds = 720
    public static let cooperTargets = [2200, 2400, 2600, 2700]
    public static let trackLapMeters = 400
    /// How far behind the even pace the runner may fall before the watch alerts.
    public static let paceToleranceMeters = 50.0

    /// TFF upper time limits for the timed drills, by test and level ("klasman" or "ust").
    private static let sprintLimits: [String: [String: Double]] = [
        "sprint40": ["klasman": 6.1, "ust": 6.0],
        "sprint30": ["klasman": 4.8, "ust": 4.6],
        "coda": ["klasman": 10.1, "ust": 9.8],
    ]

    public static func sprintLimit(test: String, level: String) -> Double {
        sprintLimits[test]![level]!
    }

    public enum PaceAlert: String, Sendable { case behind, recovered }

    /// Meters ahead (positive) or behind (negative) the even pace that reaches the target at 12:00.
    public static func cooperDelta(targetMeters: Int, elapsedSeconds: Double, meters: Double) -> Double {
        meters - Double(targetMeters) * elapsedSeconds / Double(cooperSeconds)
    }

    public static func paceAlert(wasBehind: Bool, delta: Double) -> (behind: Bool, alert: PaceAlert?) {
        if !wasBehind { return delta < -paceToleranceMeters ? (true, .behind) : (false, nil) }
        return delta >= 0 ? (false, .recovered) : (true, nil)
    }

    /// The Cooper distance from full track laps plus the meters of the unfinished one.
    public static func correctedCooperMeters(laps: Double, extraMeters: Double) -> Int? {
        guard laps == laps.rounded(.down), laps >= 1 else { return nil }
        guard extraMeters == extraMeters.rounded(.down), extraMeters >= 0, extraMeters < Double(trackLapMeters) else { return nil }
        return Int(laps) * trackLapMeters + Int(extraMeters)
    }

    /// A `fitness_session` message: the event batch shape with a `fitness` field.
    public static func encodeSession(
        id: String, deviceID: String, test: String, value: Double, detail: [String: Any], recordedAt: Date
    ) throws -> Data {
        let body: [String: Any] = [
            "schemaVersion": 1,
            "batchID": id,
            "matchID": id,
            "senderDeviceID": deviceID,
            "events": [Any](),
            "fitness": [
                "id": id,
                "test": test,
                "value": value,
                "recordedAt": Int64((recordedAt.timeIntervalSince1970 * 1000).rounded()),
                "detail": detail,
            ] as [String: Any],
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }
}
