import Foundation
import Security
import CryptoKit

struct LastPlaybackRecord: Codable, Equatable, Identifiable {
    let sourceID: UUID?
    let title: String
    let group: String
    let url: URL
    let metadata: MediaMetadata?
    let isLive: Bool
    let position: Double
    let duration: Double
    let updatedAt: Date

    init(channel: MediaChannel, sourceID: UUID?, position: Double, duration: Double, isLive: Bool, updatedAt: Date = Date()) {
        self.sourceID = sourceID; title = channel.title; group = channel.group; url = channel.url
        metadata = channel.metadata
        self.isLive = isLive; self.updatedAt = updatedAt
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.position = position.isFinite ? max(0, position) : 0
    }
    private enum CodingKeys: String, CodingKey { case sourceID, title, group, url, metadata, isLive, position, duration, updatedAt }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(channel: MediaChannel(title: try values.decode(String.self, forKey: .title),
                                       group: try values.decode(String.self, forKey: .group),
                                       url: try values.decode(URL.self, forKey: .url),
                                       metadata: try values.decodeIfPresent(MediaMetadata.self, forKey: .metadata) ?? MediaMetadata()),
                  sourceID: try values.decodeIfPresent(UUID.self, forKey: .sourceID),
                  position: try values.decode(Double.self, forKey: .position),
                  duration: try values.decode(Double.self, forKey: .duration),
                  isLive: try values.decode(Bool.self, forKey: .isLive),
                  updatedAt: try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast)
    }
    var channel: MediaChannel { MediaChannel(title: title, group: group, url: url, metadata: metadata ?? MediaMetadata()) }
    var resumePosition: Double {
        guard !isLive, duration <= 0 || position < duration - 2 else { return 0 }
        return position
    }
    var isFinished: Bool { !isLive && duration > 0 && position >= duration * 0.95 }
    var isInProgress: Bool { !isLive && position >= 30 && !isFinished }
    var progress: Double? { duration > 0 ? min(1, max(0, position / duration)) : nil }
    var episode: MediaEpisode? { isLive ? nil : MediaEpisode.parse(title) }
    var seriesTitle: String? { episode?.seriesTitle }
    // Hash identifiers so accessibility identifiers never expose stream credentials.
    var id: String {
        let content = seriesTitle.map { "series:" + $0.lowercased() } ?? "url:" + url.absoluteString
        return SHA256.hash(data: Data(((sourceID?.uuidString ?? "") + "|" + content).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

/// Credential-bearing resume URLs stay in device-only Keychain storage.
@MainActor
final class LastPlaybackStore: ObservableObject {
    static let shared = LastPlaybackStore()
    static let maximumEntries = 30
    @Published private(set) var record: LastPlaybackRecord?
    @Published private(set) var entries: [LastPlaybackRecord] = []
    private struct Snapshot: Codable {
        let record: LastPlaybackRecord?
        let entries: [LastPlaybackRecord]
    }
    private let account: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.alperbicer.carmirror.last-playback",
         kSecAttrAccount as String: account]
    }
    init(account: String = "last-watched") {
        self.account = account
        var read = query
        read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            if let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
                record = saved.record
                var seen: Set<String> = []
                entries = Array((saved.entries + [saved.record].compactMap { $0 }).filter { $0.isInProgress }
                    .sorted { $0.updatedAt > $1.updatedAt }
                    .filter { seen.insert($0.id).inserted }.prefix(Self.maximumEntries))
            } else if let legacy = try? JSONDecoder().decode(LastPlaybackRecord.self, from: data) {
                record = legacy
                if legacy.isInProgress { entries = [legacy] }
            }
        }
    }
    func save(_ record: LastPlaybackRecord) throws {
        guard ["http", "https"].contains(record.url.scheme?.lowercased() ?? "") else { throw LibraryError.unsupportedURL }
        var next = entries
        if record.isInProgress {
            next.removeAll { $0.id == record.id }
            next.insert(record, at: 0)
        } else if record.isFinished {
            // Finishing an older episode must not erase progress in a newer one.
            next.removeAll { $0.id == record.id && $0.url == record.url }
        }
        try persist(record: record, entries: Array(next.prefix(Self.maximumEntries)))
    }
    func remove(id: String) throws {
        try persist(record: record?.id == id ? nil : record, entries: entries.filter { $0.id != id })
    }
    func clear(sourceID: UUID? = nil) throws {
        guard let sourceID else { try persist(record: nil, entries: []); return }
        try persist(record: record?.sourceID == sourceID ? nil : record, entries: entries.filter { $0.sourceID != sourceID })
    }
    private func persist(record: LastPlaybackRecord?, entries: [LastPlaybackRecord]) throws {
        if record == nil && entries.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw LibraryError.storage }
        } else {
            let data = try JSONEncoder().encode(Snapshot(record: record, entries: entries))
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LibraryError.storage }
            } else if status != errSecSuccess { throw LibraryError.storage }
        }
        self.record = record; self.entries = entries
    }
}

enum SourceKeychain {
    private static let service = "com.alperbicer.carmirror.sources"
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }
    static func read(_ id: UUID) throws -> SourceSecret {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { throw LibraryError.storage }
        return try JSONDecoder().decode(SourceSecret.self, from: data)
    }
    static func save(_ secret: SourceSecret, id: UUID) throws {
        let data = try JSONEncoder().encode(secret)
        let update = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw LibraryError.storage }
        var item = query(id)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LibraryError.storage }
    }
    static func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LibraryError.storage }
    }
}

/// Keep playback sources accessible after the first unlock, including during locked CarPlay sessions.
private enum SourceFileProtection {
    static func migrateFile(_ file: URL) throws {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: file.path)
    }

    static func prepareDirectory(_ directory: URL, migratingExistingFiles: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try migrateFile(directory)
        if migratingExistingFiles {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                try migrateFile(file)
            }
        }
    }
}

@MainActor
final class SourceLibrary: ObservableObject {
    static let shared = SourceLibrary()
    @Published private(set) var sources: [MediaSource] = []
    @Published var message: String?
    private let file: URL
    private let importedPlaylists: URL
    private let tracksUserHistory: Bool
    private let channelCache: SourceChannelCache
    let accounts: SourceAccountStore
    init(directory: URL? = nil, accountLoad: (@MainActor (MediaSource) async throws -> IPTVAccountInfo?)? = nil) {
        tracksUserHistory = directory == nil
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Library", isDirectory: true)
        file = directory.appendingPathComponent("sources.json")
        importedPlaylists = directory.appendingPathComponent("Playlists", isDirectory: true)
        channelCache = SourceChannelCache(directory: directory.appendingPathComponent("ChannelCache", isDirectory: true))
        accounts = SourceAccountStore(file: directory.appendingPathComponent("account-expiry.json"), load: accountLoad)
        do {
            try SourceFileProtection.prepareDirectory(directory)
            try SourceFileProtection.migrateFile(file)
            try SourceFileProtection.prepareDirectory(importedPlaylists, migratingExistingFiles: true)
            var directory = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            if FileManager.default.fileExists(atPath: file.path) {
                sources = try JSONDecoder().decode([MediaSource].self, from: Data(contentsOf: file))
            }
        } catch { message = L10n.tr("Kaynaklar açılamadı. Lütfen yeniden dene.") }
    }
    func add(name: String, kind: MediaSourceKind, secret: SourceSecret, access: ProductAccess) throws {
        guard access.canAddSource(count: sources.count), !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw LibraryError.storage }
        try validate(kind: kind, secret: secret)
        let source = MediaSource(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind)
        try SourceKeychain.save(secret, id: source.id)
        do { try persist(sources + [source]); sources.append(source) }
        catch { try? SourceKeychain.delete(source.id); throw error }
    }
    func delete(_ source: MediaSource) throws {
        let oldSecret = try? SourceKeychain.read(source.id)
        let next = sources.filter { $0.id != source.id }
        try removeSources([source], keeping: next)
        channelCache.invalidate(source.id)
        accounts.invalidate(source.id)
        if tracksUserHistory {
            MirrorModel.shared.discardLastPlayback(sourceID: source.id)
            try MediaFavorites.shared.clear(sourceID: source.id)
        }
        removeImportedPlaylist(oldSecret?.url)
    }
    func update(_ source: MediaSource, name: String, kind: MediaSourceKind, secret: SourceSecret) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = sources.firstIndex(where: { $0.id == source.id }) else { throw LibraryError.storage }
        try validate(kind: kind, secret: secret)
        let previousSecret = try SourceKeychain.read(source.id)
        var next = sources
        next[index] = MediaSource(id: source.id, name: name, kind: kind)
        try SourceKeychain.save(secret, id: source.id)
        do { try persist(next) }
        catch {
            try SourceKeychain.save(previousSecret, id: source.id)
            throw error
        }
        sources = next
        if previousSecret.url != secret.url { removeImportedPlaylist(previousSecret.url) }
        channelCache.invalidate(source.id)
        accounts.invalidate(source.id)
        if tracksUserHistory {
            MirrorModel.shared.discardLastPlayback(sourceID: source.id)
            if source.kind != kind || previousSecret.url != secret.url ||
                previousSecret.username != secret.username || previousSecret.password != secret.password {
                try MediaFavorites.shared.clear(sourceID: source.id)
            }
        }
        let updatedSource = next[index]
        // Credentials can change while the source's visible name/kind stay identical.
        // In that case a SwiftUI task keyed by MediaSource would not run again.
        Task { [weak self] in
            guard let self, self.sources.contains(updatedSource) else { return }
            await self.accounts.refresh(for: updatedSource)
        }
    }
    func clear() throws {
        let previousFiles = sources.compactMap { try? SourceKeychain.read($0.id).url }
        try removeSources(sources, keeping: [])
        channelCache.removeAll()
        accounts.removeAll()
        if tracksUserHistory {
            MediaArtworkStore.shared.removeAll()
            MirrorModel.shared.discardLastPlayback()
            try MediaFavorites.shared.clear()
        }
        for url in previousFiles { removeImportedPlaylist(url) }
    }

    private func removeSources(_ removed: [MediaSource], keeping next: [MediaSource]) throws {
        let previous = sources
        let secrets = removed.compactMap { source -> (UUID, SourceSecret)? in
            (try? SourceKeychain.read(source.id)).map { (source.id, $0) }
        }
        // Disk-full / protection failures must leave credentials untouched.
        try persist(next)
        do {
            for source in removed { try SourceKeychain.delete(source.id) }
        } catch {
            for (id, secret) in secrets { try? SourceKeychain.save(secret, id: id) }
            try persist(previous)
            throw error
        }
        sources = next
    }
    /// Copy a user-selected file while its security scope is open. The saved source never
    /// depends on a temporary picker URL or on the original remaining in iCloud Drive.
    func importPlaylist(_ input: URL, name: String, replacing source: MediaSource? = nil, access: ProductAccess) throws {
        guard source != nil || access.canAddSource(count: sources.count) else { throw LibraryError.storage }
        let scoped = input.startAccessingSecurityScopedResource()
        defer { if scoped { input.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: M3UParser.maximumBytes + 1) ?? Data()
        let channels = try M3UParser.parse(data, baseURL: input, fallbackTitle: name)
        // A local HLS manifest cannot be served to AVPlayer as a remote channel.
        guard channels.allSatisfy({ !$0.url.isFileURL }) else { throw LibraryError.unsupportedURL }
        try SourceFileProtection.prepareDirectory(importedPlaylists)
        let destination = importedPlaylists.appendingPathComponent(UUID().uuidString + ".m3u")
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        do {
            let secret = SourceSecret(url: destination)
            if let source { try update(source, name: name, kind: .playlistFile, secret: secret) }
            else { try add(name: name, kind: .playlistFile, secret: secret, access: access) }
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    private func ownsImportedPlaylist(_ url: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL.deletingLastPathComponent() == importedPlaylists.standardizedFileURL
            && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil && url.pathExtension == "m3u"
    }
    private func removeImportedPlaylist(_ url: URL?) {
        if let url, ownsImportedPlaylist(url) { try? FileManager.default.removeItem(at: url) }
    }
    private func validate(kind: MediaSourceKind, secret: SourceSecret) throws {
        if kind == .playlistFile {
            guard ownsImportedPlaylist(secret.url), FileManager.default.fileExists(atPath: secret.url.path) else { throw LibraryError.unsupportedURL }
        } else {
            _ = try MediaURL.validate(secret.url.absoluteString)
            if kind == .xtream { _ = try XtreamEndpoint.playlist(secret: secret) }
        }
    }
    private func persist(_ sources: [MediaSource]) throws {
        try JSONEncoder().encode(sources).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func cachedChannels(for source: MediaSource) -> [MediaChannel]? { channelCache.cached(for: source) }
    func channels(for source: MediaSource, reload: Bool = false,
                  onCached: (@MainActor ([MediaChannel]) -> Void)? = nil) async throws -> [MediaChannel] {
        return try await channelCache.channels(for: source, reload: reload, onCached: onCached) {
            let secret = try SourceKeychain.read(source.id)
            try self.validate(kind: source.kind, secret: secret)
            return try await SourceLoader.load(source: source, secret: secret)
        }
    }
}

struct SourceAccountSnapshot: Codable, Equatable {
    let source: MediaSource
    let info: IPTVAccountInfo
    let checkedAt: Date
}

enum SourceAccountState: Equatable {
    case loading, unsupported, failed
    case information(SourceAccountSnapshot, refreshFailed: Bool)
}

/// Metadata refreshes are independent of channel loading and never prevent playback.
@MainActor
final class SourceAccountStore: ObservableObject {
    @Published private var states: [UUID: SourceAccountState] = [:]
    private var snapshots: [UUID: SourceAccountSnapshot] = [:]
    private var versions: [UUID: MediaSource] = [:]
    private var attempts: [UUID: Date] = [:]
    private var pending: [UUID: (UUID, Task<IPTVAccountInfo?, Error>)] = [:]
    private let file: URL?
    private let load: @MainActor (MediaSource) async throws -> IPTVAccountInfo?

    init(file: URL? = nil, load: (@MainActor (MediaSource) async throws -> IPTVAccountInfo?)? = nil) {
        self.file = file
        self.load = load ?? SourceAccountLoader.load
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([SourceAccountSnapshot].self, from: data) {
            for snapshot in saved {
                snapshots[snapshot.source.id] = snapshot
                versions[snapshot.source.id] = snapshot.source
                states[snapshot.source.id] = .information(snapshot, refreshFailed: false)
            }
        }
    }

    func state(for source: MediaSource) -> SourceAccountState? {
        guard versions[source.id] == source else { return nil }
        return states[source.id]
    }

    func refresh(for source: MediaSource, force: Bool = false, now: Date = Date()) async {
        guard source.kind != .stream else { return }
        if let previous = versions[source.id], previous != source { invalidate(source.id) }
        if let request = pending[source.id] { _ = try? await request.1.value; return }
        if !force {
            if state(for: source) == .unsupported { return }
            if let attempted = attempts[source.id], now.timeIntervalSince(attempted) < 60 { return }
            if let saved = snapshots[source.id], now.timeIntervalSince(saved.checkedAt) < 900 { return }
        }
        versions[source.id] = source
        attempts[source.id] = now
        if snapshots[source.id] == nil { states[source.id] = .loading }
        let generation = UUID()
        let task = Task { try await load(source) }
        pending[source.id] = (generation, task)
        do {
            let info = try await task.value
            guard pending[source.id]?.0 == generation else { return }
            pending[source.id] = nil
            if let info {
                let snapshot = SourceAccountSnapshot(source: source, info: info, checkedAt: now)
                snapshots[source.id] = snapshot
                states[source.id] = .information(snapshot, refreshFailed: false)
            } else {
                snapshots[source.id] = nil
                states[source.id] = .unsupported
            }
            persist()
        } catch {
            guard pending[source.id]?.0 == generation else { return }
            pending[source.id] = nil
            if let snapshot = snapshots[source.id] {
                states[source.id] = .information(snapshot, refreshFailed: true)
            } else { states[source.id] = .failed }
        }
    }

    func invalidate(_ id: UUID) {
        pending.removeValue(forKey: id)?.1.cancel()
        snapshots[id] = nil; versions[id] = nil; attempts[id] = nil; states[id] = nil
        persist()
    }
    func removeAll() {
        pending.values.forEach { $0.1.cancel() }
        pending.removeAll(); snapshots.removeAll(); versions.removeAll(); attempts.removeAll(); states.removeAll()
        persist()
    }
    private func persist() {
        guard let file else { return }
        try? JSONEncoder().encode(Array(snapshots.values)).write(to: file, options: [.atomic, .completeFileProtection])
    }
}

private enum SourceAccountLoader {
    static func load(source: MediaSource) async throws -> IPTVAccountInfo? {
        let secret = try SourceKeychain.read(source.id)
        guard let url = try XtreamEndpoint.accountInfo(kind: source.kind, secret: secret) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Mirivo/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        let maximumBytes = 64 * 1_024
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.expectedContentLength <= maximumBytes else { throw LibraryError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw LibraryError.tooLarge }
            data.append(byte)
        }
        return try IPTVAccountInfo.parse(data)
    }
}

enum SourceLoader {
    static func load(source: MediaSource, secret: SourceSecret) async throws -> [MediaChannel] {
        if source.kind == .stream { return [MediaChannel(title: source.name, url: try MediaURL.validate(secret.url.absoluteString))] }
        if source.kind == .playlistFile {
            let handle = try FileHandle(forReadingFrom: secret.url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: M3UParser.maximumBytes + 1) ?? Data()
            return try M3UParser.parse(data, baseURL: secret.url, fallbackTitle: source.name)
        }
        let url = try source.kind == .xtream ? XtreamEndpoint.playlist(secret: secret) : XtreamEndpoint.nativePlaylistURL(secret.url)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Mirivo/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw LibraryError.invalidResponse }
        guard response.expectedContentLength <= M3UParser.maximumBytes else { throw LibraryError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < M3UParser.maximumBytes else { throw LibraryError.tooLarge }
            data.append(byte)
        }
        return try M3UParser.parse(data, baseURL: response.url ?? url, fallbackTitle: source.name)
    }
}

/// Show saved channels immediately, then refresh lists older than 24 hours.
/// Credential-bearing URLs are encrypted with a device-only Keychain key.
@MainActor
final class SourceChannelCache {
    static let lifetime: TimeInterval = 24 * 60 * 60
    private struct Snapshot: Codable, Sendable {
        struct Channel: Codable, Sendable {
            let title: String
            let group: String
            let url: URL
            let metadata: MediaMetadata
            init(_ channel: MediaChannel) {
                title = channel.title; group = channel.group; url = channel.url; metadata = channel.metadata
            }
            var value: MediaChannel { MediaChannel(title: title, group: group, url: url, metadata: metadata) }
        }
        let source: MediaSource
        let savedAt: Date
        let channels: [Channel]
    }
    private var values: [UUID: (source: MediaSource, channels: [MediaChannel], savedAt: Date)] = [:]
    private var accesses: [UUID: UInt64] = [:]
    private var accessCounter: UInt64 = 0
    private let maximumMemorySources: Int
    private let maximumMemoryChannels: Int
    private var pending: [UUID: (token: UUID, source: MediaSource, task: Task<[MediaChannel], Error>)] = [:]
    private var observers: [UUID: [@MainActor ([MediaChannel]) -> Void]] = [:]
    private var attempts: [UUID: Date] = [:]
    private let directory: URL?
    private let key: SymmetricKey?

    init(directory: URL? = nil, encryptionKey: SymmetricKey? = nil,
         maximumMemorySources: Int = 4, maximumMemoryChannels: Int = 40_000) {
        self.maximumMemorySources = max(1, maximumMemorySources)
        self.maximumMemoryChannels = max(1, maximumMemoryChannels)
        self.directory = directory
        key = directory == nil ? nil : (encryptionKey ?? (try? Self.deviceKey()))
        if let directory {
            try? SourceFileProtection.prepareDirectory(directory, migratingExistingFiles: true)
            var excluded = directory
            var resources = URLResourceValues(); resources.isExcludedFromBackup = true
            try? excluded.setResourceValues(resources)
        }
    }

    func cached(for source: MediaSource) -> [MediaChannel]? {
        guard let entry = values[source.id], entry.source == source else { return nil }
        touch(source.id)
        return entry.channels
    }

    private func touch(_ id: UUID) {
        accessCounter &+= 1
        accesses[id] = accessCounter
    }

    private func trimMemory(keeping id: UUID) {
        touch(id)
        var count = values.values.reduce(0) { $0 + $1.channels.count }
        let oldest = values.keys.filter { $0 != id }.sorted { (accesses[$0] ?? 0) < (accesses[$1] ?? 0) }
        for key in oldest {
            guard values.count > maximumMemorySources || count > maximumMemoryChannels else { break }
            count -= values.removeValue(forKey: key)?.channels.count ?? 0
            accesses[key] = nil
        }
    }

    func channels(for source: MediaSource, reload: Bool = false, now: Date = Date(),
                  onCached: (@MainActor ([MediaChannel]) -> Void)? = nil,
                  load: @escaping @MainActor () async throws -> [MediaChannel]) async throws -> [MediaChannel] {
        if let entry = values[source.id], entry.source != source { invalidate(source.id) }
        if let entry = pending[source.id], entry.source != source { invalidate(source.id) }
        if let channels = cached(for: source) {
            onCached?(channels)
            if !reload, let saved = values[source.id], isFresh(saved.savedAt, now: now) { return channels }
        } else if let onCached { observers[source.id, default: []].append(onCached) }
        if let entry = pending[source.id] {
            let channels = try await entry.task.value
            guard !entry.task.isCancelled else { throw CancellationError() }
            return channels
        }
        let generation = UUID()
        let task = Task {
            // Decode large playlists away from the UI thread, including on a cold launch.
            if self.values[source.id] == nil, let file = self.file(source.id), let key = self.key {
                let snapshot = await Task.detached(priority: .utility) { () -> (Snapshot, [MediaChannel])? in
                    guard let data = try? Data(contentsOf: file),
                          let box = try? AES.GCM.SealedBox(combined: data),
                          let plaintext = try? AES.GCM.open(box, using: key),
                          let snapshot = try? JSONDecoder().decode(Snapshot.self, from: plaintext),
                          snapshot.source == source else { return nil }
                    return (snapshot, snapshot.channels.map(\.value))
                }.value
                try Task.checkCancellation()
                if let (snapshot, channels) = snapshot {
                    self.values[source.id] = (source, channels, snapshot.savedAt)
                    self.trimMemory(keeping: source.id)
                    self.observers.removeValue(forKey: source.id)?.forEach { $0(channels) }
                }
            }
            let saved = self.values[source.id]
            if !reload, let saved {
                if self.isFresh(saved.savedAt, now: now) { return saved.channels }
                // Avoid retrying on every navigation while offline.
                if let attempt = self.attempts[source.id], now.timeIntervalSince(attempt) < 300 { return saved.channels }
            }
            self.attempts[source.id] = now
            do {
                let channels = try await load()
                try Task.checkCancellation()
                self.values[source.id] = (source, channels, now)
                self.trimMemory(keeping: source.id)
                if let file = self.file(source.id), let key = self.key {
                    let data = await Task.detached(priority: .utility) { () -> Data? in
                        let snapshot = Snapshot(source: source, savedAt: now, channels: channels.map(Snapshot.Channel.init))
                        guard let plaintext = try? JSONEncoder().encode(snapshot) else { return nil }
                        return try? AES.GCM.seal(plaintext, using: key).combined
                    }.value
                    try Task.checkCancellation()
                    if let data { try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
                }
                return channels
            } catch {
                try Task.checkCancellation()
                if !reload, let saved { return saved.channels }
                throw error
            }
        }
        pending[source.id] = (generation, source, task)
        do {
            let channels = try await task.value
            guard pending[source.id]?.token == generation else { throw CancellationError() }
            pending[source.id] = nil
            observers[source.id] = nil
            return channels
        } catch {
            if pending[source.id]?.token == generation { pending[source.id] = nil; observers[source.id] = nil }
            throw error
        }
    }

    private func isFresh(_ date: Date, now: Date) -> Bool {
        (0..<Self.lifetime).contains(now.timeIntervalSince(date))
    }
    private func file(_ id: UUID) -> URL? { directory?.appendingPathComponent(id.uuidString + ".encrypted") }
    func invalidate(_ id: UUID) {
        pending.removeValue(forKey: id)?.task.cancel()
        values[id] = nil; accesses[id] = nil; attempts[id] = nil; observers[id] = nil
        if let file = file(id) { try? FileManager.default.removeItem(at: file) }
    }
    func removeAll() {
        pending.values.forEach { $0.task.cancel() }
        pending.removeAll(); values.removeAll(); accesses.removeAll(); attempts.removeAll(); observers.removeAll()
        if let directory {
            for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func deviceKey() throws -> SymmetricKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "com.alperbicer.carmirror.channel-cache",
                                   kSecAttrAccount as String: "encryption-key"]
        var read = query
        read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw LibraryError.storage }
        let key = SymmetricKey(size: .bits256)
        var item = query
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LibraryError.storage }
        return key
    }
}
