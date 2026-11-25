import Foundation
import Testing
@testable import RefAppWatchCore

/// docs/watch-protocol/vectors/fitness.json, the file the phone and Wear OS tests use too.
private func fitnessVectors() throws -> [String: Any] {
    let dir = ProcessInfo.processInfo.environment["VECTORS_DIR"]
        ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../docs/watch-protocol/vectors").path
    let data = try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("fitness.json"))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func cooperDeltaMatchesTheVectors() throws {
    for item in try #require(try fitnessVectors()["cooperDelta"] as? [[String: Any]]) {
        let delta = Fitness.cooperDelta(
            targetMeters: (item["target"] as! NSNumber).intValue,
            elapsedSeconds: (item["elapsedSec"] as! NSNumber).doubleValue,
            meters: (item["meters"] as! NSNumber).doubleValue
        )
        #expect(abs(delta - (item["delta"] as! NSNumber).doubleValue) < 1e-6)
    }
}

@Test func paceAlertMatchesTheVectors() throws {
    for item in try #require(try fitnessVectors()["paceAlert"] as? [[String: Any]]) {
        let result = Fitness.paceAlert(wasBehind: item["wasBehind"] as! Bool, delta: (item["delta"] as! NSNumber).doubleValue)
        #expect(result.behind == item["behind"] as! Bool)
        #expect(result.alert?.rawValue == item["alert"] as? String)
    }
}

@Test func lapCorrectionMatchesTheVectors() throws {
    for item in try #require(try fitnessVectors()["corrected"] as? [[String: Any]]) {
        let meters = Fitness.correctedCooperMeters(laps: (item["laps"] as! NSNumber).doubleValue, extraMeters: (item["extra"] as! NSNumber).doubleValue)
        #expect(meters == (item["meters"] as? NSNumber)?.intValue)
    }
}

@Test func aSessionTravelsAsAFitnessBatch() throws {
    let data = try Fitness.encodeSession(
        id: "S1", deviceID: "D1", test: "cooper", value: 2650,
        detail: ["targetMeters": 2600, "corrected": true], recordedAt: Date(timeIntervalSince1970: 1_764_000_000)
    )
    let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(body["batchID"] as? String == "S1")
    #expect(body["matchID"] as? String == "S1")
    #expect((body["events"] as? [Any])?.isEmpty == true)
    let fitness = try #require(body["fitness"] as? [String: Any])
    #expect(fitness["test"] as? String == "cooper")
    #expect((fitness["recordedAt"] as? NSNumber)?.int64Value == 1_764_000_000_000)
    #expect((fitness["detail"] as? [String: Any])?["corrected"] as? Bool == true)
}
