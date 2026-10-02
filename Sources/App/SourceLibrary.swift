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
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Library", isDirectory: true)
        file = directory.appendingPathComponent("sources.json")
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
        _ = try MediaURL.validate(secret.url.absoluteString)
        let source = MediaSource(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind)
        try SourceKeychain.save(secret, id: source.id)
        do { try persist(sources + [source]); sources.append(source) }
        catch { try? SourceKeychain.delete(source.id); throw error }
    }
    func delete(_ source: MediaSource) throws {
        try SourceKeychain.delete(source.id)
        let next = sources.filter { $0.id != source.id }
        try persist(next); sources = next
    }
    func clear() throws {
        for source in sources { try SourceKeychain.delete(source.id) }
        try persist([]); sources = []
    }
    private func persist(_ sources: [MediaSource]) throws {
        try JSONEncoder().encode(sources).write(to: file, options: [.atomic, .completeFileProtection])
    }
    func channels(for source: MediaSource) async throws -> [MediaChannel] {
        let secret = try SourceKeychain.read(source.id)
        return try await SourceLoader.load(source: source, secret: secret)
    }
}

private enum SourceLoader {
    static func load(source: MediaSource, secret: SourceSecret) async throws -> [MediaChannel] {
        if source.kind == .stream { return [MediaChannel(title: source.name, url: secret.url)] }
        let url = try source.kind == .xtream ? XtreamEndpoint.playlist(secret: secret) : secret.url
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
