import Foundation

/// Cross-process state contains counters and ephemeral URLs, never captured images.
struct BroadcastSessionStore {
    let directory: URL

    init() throws {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "CMAppGroupIdentifier") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw NSError(domain: "CarMirror", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Paylaşılan alan açılamadı. Ana uygulama ve yayın uzantısının App Group imzasını kontrol et."])
        }
        directory = container.appendingPathComponent("LiveSession", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
    }

    func readStatus() -> CaptureStatus? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("status.json")) else { return nil }
        return try? JSONDecoder().decode(CaptureStatus.self, from: data)
    }

    func write(_ status: CaptureStatus) throws {
        try JSONEncoder().encode(status).write(to: directory.appendingPathComponent("status.json"), options: .atomic)
    }

    func requestStop(sessionID: UUID) throws {
        try JSONEncoder().encode(CaptureCommand(stop: sessionID))
            .write(to: directory.appendingPathComponent("command.json"), options: .atomic)
    }

    func shouldStop(sessionID: UUID) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("command.json")),
              let command = try? JSONDecoder().decode(CaptureCommand.self, from: data) else { return false }
        return command.sessionID == sessionID && command.action == "stop"
    }
}
