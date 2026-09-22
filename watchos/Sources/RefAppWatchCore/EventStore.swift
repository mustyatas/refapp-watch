import Foundation

public actor EventStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    public func load() throws -> [MatchEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([MatchEvent].self, from: Data(contentsOf: fileURL))
    }

    @discardableResult
    public func append(_ event: MatchEvent) throws -> [MatchEvent] {
        var events = try load()
        if !events.contains(where: { $0.id == event.id }) { events.append(event) }
        let data = try encoder.encode(events)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        return events
    }
}
