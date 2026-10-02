import Foundation

/// Each process creates its own serial writer; the journal also locks across processes.
final class SessionDiagnostics: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CarMirror.Diagnostics", qos: .utility)
    private let journal: DiagnosticJournal?
    private let process: DiagnosticProcess

    init(process: DiagnosticProcess) {
        self.process = process
        if let identifier = Bundle.main.object(forInfoDictionaryKey: "CMAppGroupIdentifier") as? String,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            let directory = container.appendingPathComponent("Library/Caches/Diagnostics", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var excluded = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? excluded.setResourceValues(values)
            journal = DiagnosticJournal(directory: directory)
        } else { journal = nil }
    }

    func record(_ kind: DiagnosticKind, sessionID: UUID, values: DiagnosticValues = DiagnosticValues()) {
        let event = DiagnosticEvent(sessionID: sessionID, process: process, kind: kind, values: values)
        queue.async { [journal] in try? journal?.append(event) }
    }

    func flush() { queue.sync {} }

    func export() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [journal] in
                do {
                    guard let journal else { throw CocoaError(.fileReadNoSuchFile) }
                    let report = DiagnosticReport(
                        appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                        events: try journal.events())
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticExports", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for old in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                        try? FileManager.default.removeItem(at: old)
                    }
                    let url = directory.appendingPathComponent("CarMirror-\(UUID().uuidString).json")
                    try report.data().write(to: url, options: .atomic)
                    continuation.resume(returning: url)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func clear() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [journal] in
                do {
                    guard let journal else { throw CocoaError(.fileReadNoSuchFile) }
                    try journal.clear()
                    continuation.resume()
                }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
