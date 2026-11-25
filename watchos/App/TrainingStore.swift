import Foundation

/// Finished training sessions waiting for the phone (docs/watch-protocol/README.md, section 8).
/// Each is a file until the phone acknowledges it, like the GPS track chunks.
@MainActor
final class TrainingStore {
    var send: (Data) -> Void = { _ in }

    private let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("training", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    var lastCooperTarget: Int {
        get { UserDefaults.standard.object(forKey: "refapp.watch.last-cooper-target") as? Int ?? 2600 }
        set { UserDefaults.standard.set(newValue, forKey: "refapp.watch.last-cooper-target") }
    }

    func save(test: String, value: Double, detail: [String: Any], deviceID: String, at date: Date) {
        let id = UUID().uuidString
        guard let data = try? Fitness.encodeSession(id: id, deviceID: deviceID, test: test, value: value, detail: detail, recordedAt: date) else { return }
        try? data.write(to: directory.appendingPathComponent("\(id).json"), options: .atomic)
        send(data)
    }

    func pendingSessions() -> [Data] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? Data(contentsOf: $0) }
    }

    func acknowledge(id: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json"))
    }
}
