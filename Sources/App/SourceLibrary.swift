import Foundation
import Security

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

@MainActor
final class SourceLibrary: ObservableObject {
    static let shared = SourceLibrary()
    @Published private(set) var sources: [MediaSource] = []
    @Published var message: String?
    private let file: URL
    private let importedPlaylists: URL
    private let channelCache = SourceChannelCache()
    let accounts: SourceAccountStore
    init(directory: URL? = nil, accountLoad: (@MainActor (MediaSource) async throws -> IPTVAccountInfo?)? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Library", isDirectory: true)
        file = directory.appendingPathComponent("sources.json")
        importedPlaylists = directory.appendingPathComponent("Playlists", isDirectory: true)
        accounts = SourceAccountStore(file: directory.appendingPathComponent("account-expiry.json"), load: accountLoad)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
        try SourceKeychain.delete(source.id)
        let next = sources.filter { $0.id != source.id }
        try persist(next); sources = next
        channelCache.invalidate(source.id)
        accounts.invalidate(source.id)
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
        for source in sources { try SourceKeychain.delete(source.id) }
        try persist([]); sources = []
        channelCache.removeAll()
        accounts.removeAll()
        for url in previousFiles { removeImportedPlaylist(url) }
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
        try FileManager.default.createDirectory(at: importedPlaylists, withIntermediateDirectories: true)
        let destination = importedPlaylists.appendingPathComponent(UUID().uuidString + ".m3u")
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
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
        try JSONEncoder().encode(sources).write(to: file, options: [.atomic, .completeFileProtection])
    }
    func cachedChannels(for source: MediaSource) -> [MediaChannel]? { channelCache.cached(for: source) }
    func channels(for source: MediaSource, reload: Bool = false) async throws -> [MediaChannel] {
        if reload { channelCache.invalidate(source.id) }
        return try await channelCache.channels(for: source) {
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

/// Session-only cache: signed media URLs are never written to disk.
@MainActor
final class SourceChannelCache {
    private var values: [UUID: (MediaSource, [MediaChannel])] = [:]
    private var pending: [UUID: (UUID, Task<[MediaChannel], Error>)] = [:]
    func cached(for source: MediaSource) -> [MediaChannel]? {
        guard let entry = values[source.id], entry.0 == source else { return nil }
        return entry.1
    }
    func channels(for source: MediaSource, load: @escaping @MainActor () async throws -> [MediaChannel]) async throws -> [MediaChannel] {
        if let channels = cached(for: source) { return channels }
        if let entry = pending[source.id] {
            let channels = try await entry.1.value
            guard !entry.1.isCancelled else { throw CancellationError() }
            return channels
        }
        let generation = UUID()
        let task = Task { try await load() }
        pending[source.id] = (generation, task)
        do {
            let channels = try await task.value
            guard pending[source.id]?.0 == generation else { throw CancellationError() }
            values[source.id] = (source, channels)
            pending[source.id] = nil
            return channels
        } catch {
            if pending[source.id]?.0 == generation { pending[source.id] = nil }
            throw error
        }
    }
    func invalidate(_ id: UUID) {
        pending.removeValue(forKey: id)?.1.cancel()
        values[id] = nil
    }
    func removeAll() {
        pending.values.forEach { $0.1.cancel() }
        pending.removeAll(); values.removeAll()
    }
}
