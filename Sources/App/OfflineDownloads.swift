import AVFoundation
import Combine
import CryptoKit
import Foundation

struct OfflineDownload: Codable, Identifiable, Equatable {
    enum State: String, Codable { case preparing, downloading, finished, failed }
    let id: UUID
    let title: String
    let group: String
    let sourceID: UUID?
    let assetKey: String
    var state: State
    var progress: Double
    var taskIdentifier: Int?
    var packagePath: String?

    var localURL: URL? {
        guard state == .finished, let packagePath, FileManager.default.fileExists(atPath: packagePath) else { return nil }
        return URL(fileURLWithPath: packagePath)
    }
    var channel: MediaChannel? {
        guard let localURL else { return nil }
        return MediaChannel(title: title, group: group, url: localURL)
    }
}

enum OfflineDownloadError: LocalizedError {
    case unsupported, liveStream, protected, unavailable, storage
    var errorDescription: String? {
        switch self {
        case .unsupported: L10n.tr("Yalnızca HLS, MP4, M4V ve MOV film/dizi içerikleri indirilebilir.")
        case .liveStream: L10n.tr("Canlı yayınlar çevrimdışı izlenmek üzere indirilemez.")
        case .protected: L10n.tr("Bu içerik sağlayıcı koruması nedeniyle indirilemiyor.")
        case .unavailable: L10n.tr("İçerik şu anda indirilemiyor. Yayın bağlantısını kontrol et.")
        case .storage: L10n.tr("İndirme kaydedilemedi. Cihazındaki boş alanı kontrol et.")
        }
    }
}

@MainActor
final class OfflineDownloadStore: NSObject, ObservableObject {
    static let shared = OfflineDownloadStore()
    @Published private(set) var items: [OfflineDownload] = []
    @Published var message: String?

    private let sessionIdentifier = "com.alperbicer.carmirror.offline-downloads"
    private let fileSessionIdentifier = "com.alperbicer.carmirror.offline-files"
    private let storageURL: URL
    private var session: AVAssetDownloadURLSession!
    private var fileSession: URLSession!
    private var tasksByDownloadID: [UUID: URLSessionTask] = [:]
    private var backgroundCompletionHandlers: [String: () -> Void] = [:]

    private override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageURL = support.appendingPathComponent("offline-downloads.json")
        if let data = try? Data(contentsOf: storageURL), let decoded = try? JSONDecoder().decode([OfflineDownload].self, from: data) {
            items = decoded.filter { $0.state != .finished || $0.localURL != nil }.map { old in
                var item = old
                if item.state == .preparing || (item.state == .downloading && item.taskIdentifier == nil) { item.state = .failed }
                return item
            }
        }
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        session = AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: nil)
        let fileConfiguration = URLSessionConfiguration.background(withIdentifier: fileSessionIdentifier)
        fileConfiguration.isDiscretionary = false
        fileConfiguration.sessionSendsLaunchEvents = true
        fileSession = URLSession(configuration: fileConfiguration, delegate: self, delegateQueue: nil)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let assetTasks = await self.tasks(in: self.session)
            let fileTasks = await self.tasks(in: self.fileSession)
            let allTasks = assetTasks + fileTasks
            let activeIDs = Set(allTasks.compactMap { Self.downloadID(from: $0.taskDescription) })
            for task in allTasks {
                guard let id = Self.downloadID(from: task.taskDescription), var item = self.items.first(where: { $0.id == id }) else {
                    task.cancel(); continue
                }
                item.state = .downloading
                self.replace(item)
                self.tasksByDownloadID[id] = task
            }
            for index in self.items.indices where self.items[index].state == .downloading &&
                !activeIDs.contains(self.items[index].id) {
                self.items[index].state = .failed
                self.items[index].taskIdentifier = nil
            }
            self.persist()
        }
    }

    var finishedItems: [OfflineDownload] { items.filter { $0.localURL != nil } }
    var activeItems: [OfflineDownload] { items.filter { $0.state == .preparing || $0.state == .downloading } }

    func handleBackgroundEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == sessionIdentifier || identifier == fileSessionIdentifier else { completionHandler(); return }
        backgroundCompletionHandlers[identifier] = completionHandler
    }

    private func tasks(in session: URLSession) async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { continuation.resume(returning: $0) }
        }
    }

    func contains(_ channel: MediaChannel) -> Bool {
        let key = Self.assetKey(for: channel.url)
        return items.contains { $0.assetKey == key && $0.state != .failed }
    }

    func download(_ channel: MediaChannel, sourceID: UUID?) async {
        let ext = channel.url.pathExtension.lowercased()
        let hls = ext == "m3u8"
        guard ["http", "https"].contains(channel.url.scheme?.lowercased() ?? ""),
              hls || ["mp4", "m4v", "mov"].contains(ext) else {
            message = OfflineDownloadError.unsupported.localizedDescription
            return
        }
        guard !contains(channel), items.filter({ $0.state != .failed }).count < 50 else {
            message = items.filter({ $0.state != .failed }).count >= 50
                ? L10n.tr("En fazla 50 içerik indirilebilir.")
                : L10n.tr("Bu içerik zaten indirilenlerde veya indiriliyor.")
            return
        }

        let entry = OfflineDownload(id: UUID(), title: channel.title, group: channel.group,
                                    sourceID: sourceID, assetKey: Self.assetKey(for: channel.url),
                                    state: .preparing, progress: 0, taskIdentifier: nil, packagePath: nil)
        items.insert(entry, at: 0)
        persist()
        do {
            let asset = AVURLAsset(url: channel.url)
            async let playable = asset.load(.isPlayable)
            async let protected = asset.load(.hasProtectedContent)
            async let duration = asset.load(.duration)
            guard try await playable else { throw OfflineDownloadError.unavailable }
            guard try await !protected else { throw OfflineDownloadError.protected }
            let time = try await duration
            guard time.isNumeric, time.seconds.isFinite, time.seconds > 0 else { throw OfflineDownloadError.liveStream }
            if hls {
                let configuration = AVAssetDownloadConfiguration(asset: asset, title: channel.title)
                let task = session.makeAssetDownloadTask(downloadConfiguration: configuration)
                task.taskDescription = entry.id.uuidString
                var queued = entry
                queued.state = .downloading
                queued.taskIdentifier = task.taskIdentifier
                tasksByDownloadID[entry.id] = task
                replace(queued)
                persist()
                task.resume()
            } else {
                let task = fileSession.downloadTask(with: channel.url)
                task.taskDescription = "\(entry.id.uuidString)|\(ext)"
                var downloading = entry
                downloading.state = .downloading
                downloading.taskIdentifier = task.taskIdentifier
                tasksByDownloadID[entry.id] = task
                replace(downloading)
                persist()
                task.resume()
            }
        } catch {
            items.removeAll { $0.id == entry.id }
            persist()
            if error is CancellationError { return }
            message = (error as? LocalizedError)?.errorDescription ?? OfflineDownloadError.unavailable.localizedDescription
        }
    }

    func cancel(_ item: OfflineDownload) {
        tasksByDownloadID.removeValue(forKey: item.id)?.cancel()
        items.removeAll { $0.id == item.id }
        persist()
    }

    func delete(_ item: OfflineDownload) {
        tasksByDownloadID.removeValue(forKey: item.id)?.cancel()
        if let path = item.packagePath { try? FileManager.default.removeItem(atPath: path) }
        items.removeAll { $0.id == item.id }
        persist()
    }

    static func assetKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func downloadID(from description: String?) -> UUID? {
        guard let value = description?.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first else { return nil }
        return UUID(uuidString: String(value))
    }
    private func replace(_ item: OfflineDownload) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { message = OfflineDownloadError.storage.localizedDescription }
    }
}

extension OfflineDownloadStore: AVAssetDownloadDelegate, URLSessionDownloadDelegate {
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            guard let identifier = session.configuration.identifier,
                  let completion = backgroundCompletionHandlers.removeValue(forKey: identifier) else { return }
            completion()
        }
    }

    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                                didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            guard let id = Self.downloadID(from: assetDownloadTask.taskDescription), var item = items.first(where: { $0.id == id }) else { return }
            item.packagePath = location.path
            item.state = .finished
            item.progress = 1
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedURL = location
            try? protectedURL.setResourceValues(values)
            replace(item)
            tasksByDownloadID.removeValue(forKey: id)
            persist()
        }
    }

    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                                didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                                timeRangeExpectedToLoad: CMTimeRange) {
        let loaded = loadedTimeRanges.map { $0.timeRangeValue.duration.seconds }.filter(\.isFinite).reduce(0, +)
        let expected = timeRangeExpectedToLoad.duration.seconds
        let progress = expected > 0 ? min(0.99, max(0, loaded / expected)) : 0
        Task { @MainActor in
            guard let id = Self.downloadID(from: assetDownloadTask.taskDescription), var item = items.first(where: { $0.id == id }) else { return }
            item.progress = progress
            replace(item)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = min(0.99, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        Task { @MainActor in
            guard let id = Self.downloadID(from: downloadTask.taskDescription), var item = items.first(where: { $0.id == id }) else { return }
            item.progress = progress
            replace(item)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              let description = downloadTask.taskDescription?.split(separator: "|", omittingEmptySubsequences: false),
              description.count == 2, let id = UUID(uuidString: String(description[0])) else {
            Task { @MainActor in self.fail(downloadID: Self.downloadID(from: downloadTask.taskDescription)) }
            return
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineMedia", isDirectory: true)
        let destination = folder.appendingPathComponent(id.uuidString).appendingPathExtension(String(description[1]))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var excludedURL = destination
            try excludedURL.setResourceValues(values)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            Task { @MainActor in self.fail(downloadID: Self.downloadID(from: downloadTask.taskDescription)) }
            return
        }
        Task { @MainActor in
            guard var item = items.first(where: { $0.id == id }) else {
                try? FileManager.default.removeItem(at: destination)
                return
            }
            item.packagePath = destination.path
            item.state = .finished
            item.progress = 1
            item.taskIdentifier = nil
            replace(item)
            tasksByDownloadID.removeValue(forKey: id)
            persist()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil else { return }
        Task { @MainActor in self.fail(downloadID: Self.downloadID(from: task.taskDescription)) }
    }

    private func fail(downloadID: UUID?) {
        guard let downloadID, var item = items.first(where: { $0.id == downloadID }) else { return }
        item.state = .failed
        item.taskIdentifier = nil
        tasksByDownloadID.removeValue(forKey: downloadID)
        replace(item)
        message = OfflineDownloadError.unavailable.localizedDescription
        persist()
    }
}
