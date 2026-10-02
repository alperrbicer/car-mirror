import XCTest
@testable import MirrorCore

final class DiagnosticsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testReportContainsOnlyTypedFailureAndNeverNSErrorPayload() throws {
        let journal = DiagnosticJournal(directory: directory)
        var values = DiagnosticValues()
        values.failure = DiagnosticFailure(NSError(domain: "private-account-name", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "https://server.example/stream?password=private-password",
            NSURLErrorFailingURLErrorKey: URL(string: "http://127.0.0.1/secret-session-token")!
        ]))
        try journal.append(DiagnosticEvent(sessionID: UUID(), process: .app, kind: .failure, values: values))
        let data = try DiagnosticReport(appVersion: "1.0", build: "4", osVersion: "27.0", events: journal.events()).data()
        let text = String(decoding: data, as: UTF8.self)
        for sensitive in ["private-account-name", "private-password", "secret-session-token", "127.0.0.1", "server.example"] {
            XCTAssertFalse(text.contains(sensitive))
        }
        XCTAssertTrue(text.contains("\"family\":\"other\""))
        XCTAssertTrue(text.contains("\"code\":42"))
    }

    func testIndependentWritersKeepAllCompleteEvents() throws {
        let app = DiagnosticJournal(directory: directory)
        let broadcast = DiagnosticJournal(directory: directory)
        let session = UUID()
        let errors = LockedErrors()
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            do {
                let process: DiagnosticProcess = index.isMultiple(of: 2) ? .app : .broadcast
                try (process == .app ? app : broadcast).append(DiagnosticEvent(sessionID: session, process: process, kind: .streamStatistics))
            } catch { errors.append(error) }
        }
        XCTAssertTrue(errors.isEmpty)
        let reopened = try DiagnosticJournal(directory: directory).events()
        XCTAssertEqual(reopened.count, 100)
        XCTAssertEqual(reopened.filter { $0.process == .app }.count, 50)
    }

    func testRetentionKeepsNewestSessionsAndBoundsBytes() throws {
        let journal = DiagnosticJournal(directory: directory, maximumSessions: 3, maximumFileBytes: 2048)
        let sessions = (0..<5).map { _ in UUID() }
        for session in sessions {
            for _ in 0..<30 {
                try journal.append(DiagnosticEvent(sessionID: session, process: .broadcast, kind: .streamStatistics))
            }
        }
        let events = try journal.events()
        XCTAssertEqual(Set(events.map(\.sessionID)), Set(sessions.suffix(3)))
        XCTAssertLessThan(events.count, 90)
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey])!
        var bytes = 0
        for case let file as URL in files where file.pathExtension == "jsonl" {
            let count = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize!
            XCTAssertLessThanOrEqual(count, 2048)
            bytes += count
        }
        XCTAssertLessThanOrEqual(bytes, 3 * 2 * 2048)
    }

    func testClearDoesNotLeaveOldEventsInNextExport() throws {
        let journal = DiagnosticJournal(directory: directory)
        let old = UUID()
        try journal.append(DiagnosticEvent(sessionID: old, process: .app, kind: .appOpened))
        try journal.clear()
        XCTAssertTrue(try journal.events().isEmpty)
        let next = UUID()
        try journal.append(DiagnosticEvent(sessionID: next, process: .broadcast, kind: .captureStarted))
        XCTAssertEqual(try journal.events().map(\.sessionID), [next])
    }
}

private final class LockedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []
    func append(_ error: Error) { lock.lock(); errors.append(error); lock.unlock() }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return errors.isEmpty }
}
