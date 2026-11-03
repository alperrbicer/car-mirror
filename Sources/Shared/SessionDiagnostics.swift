import Foundation

/// Each process creates its own serial writer; the journal also locks across processes.
final class SessionDiagnostics: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CarMirror.Diagnostics", qos: .utility)
    private let journal: DiagnosticJournal?
    private let process: DiagnosticProcess
    private let performActivity: (DiagnosticActivity, @escaping @Sendable () -> Void) -> Void

    init(process: DiagnosticProcess,
         performActivity: ((DiagnosticActivity, @escaping @Sendable () -> Void) -> Void)? = nil) {
        self.process = process
        self.performActivity = performActivity ?? Self.performExpiringActivity
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
        enqueue { [journal] activity in try? journal?.append(event, activity: activity) }
    }

    func flush() { queue.sync {} }

    func export() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            enqueue { [journal] activity in
                do {
                    try activity.checkCancellation()
                    guard let journal else { throw CocoaError(.fileReadNoSuchFile) }
                    let report = DiagnosticReport(
                        appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                        build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                        events: try journal.events(activity: activity))
                    try activity.checkCancellation()
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DiagnosticExports", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    for old in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                        try activity.checkCancellation()
                        try? FileManager.default.removeItem(at: old)
                    }
                    let url = directory.appendingPathComponent("\(BrandIdentity.name)-\(UUID().uuidString).json")
                    try activity.checkCancellation()
                    try report.data().write(to: url, options: .atomic)
                    continuation.resume(returning: url)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func clear() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            enqueue { [journal] activity in
                do {
                    try activity.checkCancellation()
                    guard let journal else { throw CocoaError(.fileReadNoSuchFile) }
                    try journal.clear(activity: activity)
                    continuation.resume()
                }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func enqueue(_ operation: @escaping @Sendable (DiagnosticActivity) -> Void) {
        queue.async { [performActivity] in
            let activity = DiagnosticActivity()
            let finished = DispatchSemaphore(value: 0)
            performActivity(activity) {
                // An expiring activity can call back twice, or only with expired
                // when no time is granted. Continuations still complete once.
                activity.performOnce {
                    operation(activity)
                    finished.signal()
                }
            }
            // Preserve record/export/clear ordering and broadcast flush semantics
            // while the extension's activity runs on Foundation's own queue.
            finished.wait()
        }
    }

    private static func performExpiringActivity(_ activity: DiagnosticActivity,
                                               operation: @escaping @Sendable () -> Void) {
        ProcessInfo.processInfo.performExpiringActivity(withReason: "Finish diagnostic file access") { expired in
            if expired { activity.cancelAndWaitForFileAccess() }
            operation()
        }
    }
}
