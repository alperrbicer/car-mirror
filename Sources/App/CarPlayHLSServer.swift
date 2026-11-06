import Foundation
import Network

/// Serves only the generated files of one conversion, never a provider URL or
/// an arbitrary local path. Reads/writes are bounded and every session is revoked on Stop.
final class CarPlayHLSServer: @unchecked Sendable {
    let token = UUID().uuidString
    let directory: URL
    private let vod: Bool
    private let vodPlaylist: CarPlayVODPlaylist?
    var onSegmentRequested: (@Sendable (Int) -> Void)?
    private let queue = DispatchQueue(label: "Mirivo.CarPlay.HLS", qos: .userInitiated)
    private var listener: NWListener?
    private var stopped = false
    private var manifests: [String: Data] = [:]
    private var pendingResources: [UUID: (name: String, request: Data)] = [:]
    private var cachedSegments: [Int] = []
    #if DEBUG
    private var tracedRequests: Set<String> = []
    #endif
    private struct Client {
        let connection: NWConnection
        var file: FileHandle?
        var activity = Date()
    }
    private var clients: [UUID: Client] = [:]

    init(vod: Bool, playlist: CarPlayVODPlaylist? = nil) throws {
        self.vod = vod
        vodPlaylist = playlist
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Mirivo-CarPlay-\(token)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var directory = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        if let playlist {
            let body = playlist.manifest
            try body.write(to: directory.appendingPathComponent("index.m3u8"), options: .atomic)
            manifests["index.m3u8"] = body
        }
    }

    func start(host: String? = nil, onReady: @escaping @Sendable (URL) -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
        queue.async { [self] in
            guard !stopped else { return }
            guard let host = host ?? MediaRelayServer.wifiAddress() else { onFailure(URLError(.notConnectedToInternet)); return }
            do {
                let parameters = NWParameters.tcp
                parameters.prohibitedInterfaceTypes = [.cellular]
                let listener = try NWListener(using: parameters, on: .any)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] in self?.accept($0) }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, !self.stopped else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port else { onFailure(URLError(.cannotConnectToHost)); return }
                        var address = URLComponents()
                        address.scheme = "http"; address.host = host; address.port = Int(port.rawValue)
                        address.path = "/\(self.token)/index.m3u8"
                        if let url = address.url { onReady(url) } else { onFailure(URLError(.badURL)) }
                    case .failed(let error): onFailure(error)
                    default: break
                    }
                }
                listener.start(queue: queue)
            } catch { onFailure(error) }
        }
    }

    /// Snapshot only complete playlists. VLC can replace a manifest while a
    /// receiver is polling it, so retain the last valid snapshot during that write.
    func prepareSnapshot() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard !stopped else { throw CancellationError() }
                    let files = try FileManager.default.contentsOfDirectory(at: directory,
                        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
                    for file in files where file.pathExtension == "m3u8" { _ = manifest(named: file.lastPathComponent) }
                    let referenced = Set(manifests.values.flatMap { Self.resources(in: String(decoding: $0, as: UTF8.self)) })
                    var bytes = 0
                    for file in files {
                        let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                        let age = Date().timeIntervalSince(values.contentModificationDate ?? Date())
                        if file.pathExtension != "m3u8", age > 60, !referenced.contains(file.lastPathComponent) {
                            try? FileManager.default.removeItem(at: file)
                        } else { bytes += values.fileSize ?? 0 }
                    }
                    guard bytes <= 256 * 1_024 * 1_024 else { throw URLError(.dataLengthExceedsMaximum) }
                    guard let master = manifests["index.m3u8"] else { continuation.resume(returning: false); return }
                    let text = String(decoding: master, as: UTF8.self)
                    let requiredLines = text.components(separatedBy: "\n").filter { !$0.contains("TYPE=SUBTITLES") }
                    let playlists = Self.resources(in: requiredLines.joined(separator: "\n")).filter { $0.hasSuffix(".m3u8") }
                    let videoPlaylists = text.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }
                    let ready = text.contains("#EXT-X-STREAM-INF:") && !videoPlaylists.isEmpty && !playlists.isEmpty &&
                        playlists.allSatisfy { name in
                            guard let data = manifests[name] else { return false }
                            let playlist = String(decoding: data, as: UTF8.self)
                            // Sparse subtitle tracks need not hold video startup.
                            if playlist.contains(".vtt") { return true }
                            let count = playlist.components(separatedBy: "#EXTINF:").count - 1
                            return count >= 2 || (count > 0 && playlist.contains("#EXT-X-ENDLIST"))
                        }
                    continuation.resume(returning: ready)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// A ready playlist can still carry H.264 that Apple's decoder rejects.
    /// Check an actual independent fragment before handing it to the car.
    func nativeVideoSample() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    guard !stopped, let master = manifests["index.m3u8"],
                          let video = String(decoding: master, as: UTF8.self).components(separatedBy: "\n")
                            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
                          let playlist = manifests[String(video.split(separator: "/").last ?? "")] else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    let names = Self.resources(in: String(decoding: playlist, as: UTF8.self))
                    guard let initialization = names.first(where: { $0.hasSuffix(".mp4") }),
                          let fragment = names.first(where: { $0.hasSuffix(".m4s") }) else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    var data = Data()
                    for name in [initialization, fragment] {
                        let file = directory.appendingPathComponent(name)
                        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                              size <= 32 * 1_024 * 1_024 else { throw URLError(.dataLengthExceedsMaximum) }
                        data.append(try Data(contentsOf: file))
                    }
                    let sample = directory.appendingPathComponent("native-check.mp4")
                    try data.write(to: sample, options: .atomic)
                    continuation.resume(returning: sample)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func manifest(named name: String) -> Data? {
        if vodPlaylist != nil { return name == "index.m3u8" ? manifests[name] : nil }
        let file = directory.appendingPathComponent(name)
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
           let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8),
           text.hasPrefix("#EXTM3U\n"), text.hasSuffix("\n"),
           Self.resources(in: text).allSatisfy({ FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) {
            let entries = text.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }.count
            let entryTag = text.contains("#EXT-X-STREAM-INF:") ? "#EXT-X-STREAM-INF:" : "#EXTINF:"
            guard text.components(separatedBy: entryTag).count - 1 == entries else { return manifests[name] }
            var result = text.replacingOccurrences(of: "BANDWIDTH=0", with: "BANDWIDTH=4000000")
            if vod, result.contains("#EXTINF:"), !result.contains("#EXT-X-START:") {
                result = result.replacingOccurrences(of: "#EXTM3U\n", with: "#EXTM3U\n#EXT-X-START:TIME-OFFSET=0,PRECISE=YES\n")
            }
            manifests[name] = Data(result.utf8)
        }
        return manifests[name]
    }

    private static func resources(in manifest: String) -> [String] {
        manifest.components(separatedBy: "\n").flatMap { line -> [String] in
            if !line.isEmpty && !line.hasPrefix("#") { return [String(line.split(separator: "/").last ?? "")] }
            guard let start = line.range(of: "URI=\"")?.upperBound,
                  let end = line[start...].firstIndex(of: "\"") else { return [] }
            return [String(line[start..<end].split(separator: "/").last ?? "")]
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            onSegmentRequested = nil
            listener?.cancel(); listener = nil
            for id in Array(clients.keys) { close(id) }
            manifests.removeAll()
        }
    }

    func segmentReady(_ index: Int) {
        queue.async { [self] in
            guard !stopped, let playlist = vodPlaylist, playlist.interval(for: index) != nil else { return }
            retainSegment(index)
            let name = playlist.name(for: index)
            let waiting = pendingResources.filter { $0.value.name == name }
            for (id, resource) in waiting {
                pendingResources.removeValue(forKey: id)
                clients[id]?.activity = Date()
                respond(id, request: resource.request, initialRequest: false)
            }
        }
    }

    private func retainSegment(_ index: Int) {
        cachedSegments.removeAll { $0 == index }
        cachedSegments.append(index)
        // Eight 6-second, 4-Mbit segments stay well below the live server's
        // storage ceiling. An evicted segment is generated again on a seek.
        while cachedSegments.count > 8 {
            let oldest = cachedSegments.removeFirst()
            if let playlist = vodPlaylist {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(playlist.name(for: oldest)))
            }
        }
    }

    func removeOutput() {
        queue.async { [self] in try? FileManager.default.removeItem(at: directory) }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped, clients.count < 12 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = Client(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state { case .failed, .cancelled: self?.close(id); default: break }
        }
        connection.start(queue: queue)
        receive(id, data: Data())
        expire(id)
    }

    private func expire(_ id: UUID) {
        queue.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, let client = self.clients[id] else { return }
            if Date().timeIntervalSince(client.activity) >= 20 { self.close(id) } else { self.expire(id) }
        }
    }

    private func receive(_ id: UUID, data: Data) {
        guard let client = clients[id], data.count < 8_192 else { close(id); return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192 - data.count) { [weak self] bytes, _, complete, error in
            guard let self, !self.stopped else { return }
            var request = data
            if let bytes { request.append(bytes) }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil { self.respond(id, request: request) }
            else if complete || error != nil { self.close(id) }
            else { self.receive(id, data: request) }
        }
    }

    private func respond(_ id: UUID, request: Data, initialRequest: Bool = true) {
        guard let text = String(data: request, encoding: .utf8) else { reject(id, status: 400); return }
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        let prefix = "/\(token)/"
        guard first.count == 3, first[1].hasPrefix(prefix) else { reject(id, status: 404); return }
        guard first[0] == "GET" || first[0] == "HEAD" else { reject(id, status: 405); return }
        let name = String(first[1].dropFirst(prefix.count))
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard !name.isEmpty, !name.contains(".."), name.unicodeScalars.allSatisfy(allowed.contains),
              ["m3u8", "m4s", "mp4", "ts", "vtt"].contains((name as NSString).pathExtension) else { reject(id, status: 404); return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-mirivo-carplay-trace"), let client = clients[id] {
            let key = "\(client.connection.endpoint)-\((name as NSString).pathExtension)"
            if tracedRequests.count < 20, tracedRequests.insert(key).inserted {
                print("[Mirivo.CarPlay] hls-request file=\(name) peer=\(client.connection.endpoint)")
            }
        }
        #endif
        let file = directory.appendingPathComponent(name)
        if let playlist = vodPlaylist {
            guard name == "index.m3u8" || playlist.index(for: name) != nil else { reject(id, status: 404); return }
            if let index = playlist.index(for: name) {
                if !FileManager.default.fileExists(atPath: file.path) {
                    let requested = pendingResources.values.contains { $0.name == name }
                    pendingResources[id] = (name, request)
                    if !requested { onSegmentRequested?(index) }
                    return
                }
                retainSegment(index)
                // Consuming a prefetched segment advances the producer's
                // lookahead just as a cache miss does.
                if initialRequest { onSegmentRequested?(index) }
            }
        }
        let manifest = name.hasSuffix(".m3u8") ? manifest(named: name) : nil
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let fileSize = values.fileSize, fileSize <= 32 * 1_024 * 1_024 else { reject(id, status: 404); return }
        if name.hasSuffix(".m3u8") && manifest == nil { reject(id, status: 503); return }
        let size = Int64(manifest?.count ?? fileSize)
        // Each VOD TS file is an independent segment. Starting in its middle
        // can skip the reference frames needed for an accurate video seek.
        let supportsRanges = vodPlaylist == nil || !name.hasSuffix(".ts")
        let ranges = supportsRanges ? lines.dropFirst().filter { $0.lowercased().hasPrefix("range:") } : []
        let range = ranges.first.flatMap { MediaByteRange.parse(String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces), size: size) }
        guard ranges.count <= 1, ranges.isEmpty || range != nil else { reject(id, status: 416); return }
        let length = range?.length ?? size
        let type = manifest != nil ? "application/vnd.apple.mpegurl" : name.hasSuffix(".vtt") ? "text/vtt" : name.hasSuffix(".ts") ? "video/mp2t" : "video/mp4"
        var headers = "HTTP/1.1 \(range == nil ? "200 OK" : "206 Partial Content")\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\nAccept-Ranges: \(supportsRanges ? "bytes" : "none")\r\nCache-Control: no-store\r\nConnection: close\r\n"
        if let range { headers += "Content-Range: bytes \(range.start)-\(range.end)/\(size)\r\n" }
        let head = first[0] == "HEAD"
        var body: Data?
        if !head {
            if let manifest { body = manifest.subdata(in: Int(range?.start ?? 0)..<Int((range?.start ?? 0) + length)) }
            else {
                do {
                    let handle = try FileHandle(forReadingFrom: file)
                    clients[id]?.file = handle
                    try handle.seek(toOffset: UInt64(range?.start ?? 0))
                } catch { reject(id, status: 404); return }
            }
        }
        let response = Data((headers + "\r\n").utf8) + (body ?? Data())
        let completeResponse = head || body != nil
        clients[id]?.connection.send(content: response, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil || completeResponse { self.close(id) } else { self.sendBody(id, remaining: length) }
        })
    }

    private func sendBody(_ id: UUID, remaining: Int64) {
        guard !stopped, remaining > 0, let client = clients[id], let file = client.file else { close(id); return }
        do {
            guard let data = try file.read(upToCount: Int(min(65_536, remaining))), !data.isEmpty else { close(id); return }
            clients[id]?.activity = Date()
            client.connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.close(id) } else { self?.sendBody(id, remaining: remaining - Int64(data.count)) }
            })
        } catch { close(id) }
    }

    private func reject(_ id: UUID, status: Int) {
        clients[id]?.connection.send(content: Data("HTTP/1.1 \(status) Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
            completion: .contentProcessed { [weak self] _ in self?.close(id) })
    }

    private func close(_ id: UUID) {
        pendingResources.removeValue(forKey: id)
        guard let client = clients.removeValue(forKey: id) else { return }
        try? client.file?.close()
        client.connection.cancel()
    }
}
