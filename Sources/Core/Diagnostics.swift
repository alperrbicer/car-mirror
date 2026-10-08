import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum DiagnosticProcess: String, Codable, Sendable { case app, broadcast }
public enum DiagnosticKind: String, Codable, Sendable {
    case appOpened, appForegrounded, externalScreenConnected, externalScreenDisconnected
    case captureStarted, capturePaused, captureResumed, captureStopped, captureStale, firstFrame, streamReady, streamStatistics
    case playbackRequested, playbackState, externalPlaybackChanged, audioRouteChanged, audioInterrupted
    case stopRequested, failure, probeStarted, probeStopped, capturePhaseChanged
}

public enum DiagnosticReason: String, Codable, Sendable {
    case user, disconnected, interrupted, stale, replaced, finished, unavailable, preparation, capture, playback, storage
}

/// Deliberately excludes localized descriptions, URLs, userInfo and arbitrary strings.
public struct DiagnosticFailure: Codable, Equatable, Sendable {
    public enum Family: String, Codable, Sendable { case url, cocoa, avFoundation, broadcast, encoder, other }
    public let family: Family
    public let code: Int

    public init(_ error: Error) {
        let error = error as NSError
        switch error.domain {
        case NSURLErrorDomain: family = .url
        case NSCocoaErrorDomain: family = .cocoa
        case "AVFoundationErrorDomain": family = .avFoundation
        case "CarMirror": family = .broadcast
        case "CarMirror.Encoder": family = .encoder
        default: family = .other
        }
        code = error.code
    }
}

/// Typed fields prevent media URLs, account names, tokens and device names entering reports.
public struct DiagnosticValues: Codable, Equatable, Sendable {
    public enum Screen: String, Codable, Sendable { case externalInteractive, externalNonInteractive, other }
    public enum Playback: String, Codable, Sendable { case stopped, waiting, playing }
    public enum AudioRoute: String, Codable, Sendable { case car, airPlay, bluetooth, speaker, headphones, other }
    public var reason: DiagnosticReason?
    public var capturePhase: CapturePhase?
    public var screen: Screen?
    public var externalPlayback: Bool?
    public var playback: Playback?
    public var audioRoutes: [AudioRoute]?
    public var receivedFrames: Int?
    public var encodedFrames: Int?
    public var receivedAudioFrames: Int?
    public var encodedAudioFrames: Int?
    public var droppedAudioFrames: Int?
    public var droppedFrames: Int?
    public var segments: Int?
    public var bufferedBytes: Int?
    public var hasNetworkAddress: Bool?
    public var width: Int?
    public var height: Int?
    public var thermalState: Int?
    public var failure: DiagnosticFailure?
    public init() {}
}

public struct DiagnosticEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let sessionID: UUID
    public let process: DiagnosticProcess
    public let kind: DiagnosticKind
    public let values: DiagnosticValues

    public init(sessionID: UUID, process: DiagnosticProcess, kind: DiagnosticKind,
                values: DiagnosticValues = DiagnosticValues(), timestamp: Date = Date()) {
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.process = process
        self.kind = kind
        self.values = values
    }
}

public struct DiagnosticReport: Codable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let appVersion: String
    public let build: String
    public let osVersion: String
    public let events: [DiagnosticEvent]

    public init(appVersion: String, build: String, osVersion: String, events: [DiagnosticEvent]) {
        schemaVersion = 1
        generatedAt = Date()
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.events = events
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

/// A file lock serializes app/extension writes, trimming, export and clearing.
/// Each producer owns its file; at most 10 sessions x 2 x 256 KiB = 5 MiB.
public final class DiagnosticJournal: @unchecked Sendable {
    private let directory: URL
    private let maximumSessions: Int
    private let maximumFileBytes: Int
    private let threadLock = NSLock()

    public init(directory: URL, maximumSessions: Int = 10, maximumFileBytes: Int = 256 * 1024) {
        self.directory = directory
        self.maximumSessions = max(1, maximumSessions)
        self.maximumFileBytes = max(2048, maximumFileBytes)
    }

    public func append(_ event: DiagnosticEvent) throws {
        try locked {
            let session = directory.appendingPathComponent(event.sessionID.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
            let file = session.appendingPathComponent("\(event.process.rawValue).jsonl")
            var line = try JSONEncoder().encode(event)
            line.append(0x0A)
            guard line.count <= maximumFileBytes else { return }
            var data = (try? Data(contentsOf: file)) ?? Data()
            if data.count + line.count > maximumFileBytes {
                let remaining = maximumFileBytes - line.count
                data = Data(data.suffix(remaining))
                if let newline = data.firstIndex(of: 0x0A) { data = Data(data.suffix(from: data.index(after: newline))) }
                else { data = Data() }
            }
            data.append(line)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: session.path)
            try prune()
        }
    }

    public func events() throws -> [DiagnosticEvent] {
        try locked {
            try prune()
            let decoder = JSONDecoder()
            return try sessions().flatMap { session in
                DiagnosticProcess.all.map { process in
                    (try? Data(contentsOf: session.appendingPathComponent("\(process.rawValue).jsonl"))) ?? Data()
                }.flatMap { data in
                    data.split(separator: 0x0A).compactMap { try? decoder.decode(DiagnosticEvent.self, from: Data($0)) }
                }
            }.sorted { $0.timestamp < $1.timestamp }
        }
    }

    public func clear() throws {
        try locked {
            for session in try sessions() { try FileManager.default.removeItem(at: session) }
        }
    }

    private func sessions() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]).filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }

    private func prune() throws {
        let ordered = try sessions().sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for old in ordered.dropFirst(maximumSessions) { try FileManager.default.removeItem(at: old) }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        threadLock.lock()
        defer { threadLock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}

private extension DiagnosticProcess { static let all: [Self] = [.app, .broadcast] }
