import Foundation
import Network
import Darwin
#if SWIFT_PACKAGE
import MirrorCore
#endif

/// A per-playback relay, not an open proxy. Only the selected URL and URLs
/// discovered in its HLS manifests are reachable through opaque, revocable paths.
/// The phone retains provider cookies; the receiver never needs those credentials.
public final class MediaRelayServer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "Mirivo.MediaRelay", qos: .userInitiated)
    private let source: URL
    private let token = UUID().uuidString
    private var listener: NWListener?
    private var session: URLSession?
    private var baseURL: URL?
    private var stopped = false
    private struct Resource { let url: URL; var accessed: Date }
    private var resources: [String: Resource] = [:]
    private var paths: [URL: String] = [:]
    private struct Client {
        let connection: NWConnection
        var task: URLSessionDataTask?
        var response: HTTPURLResponse?
        var manifest: Data?
        var prefix = Data()
        var head = false
        var headersSent = false
        var chunks: [Data] = []
        var queuedBytes = 0
        var sending = false
        var suspended = false
        var completed = false
        var activity = Date()
    }
    private var clients: [UUID: Client] = [:]
    private var tasks: [Int: UUID] = [:]
    private let maximumManifestBytes = 1_048_576
    private let maximumBufferedBytes = 2_097_152

    public init(source: URL) throws {
        guard ["http", "https"].contains(source.scheme?.lowercased() ?? ""), source.host != nil else {
            throw URLError(.unsupportedURL)
        }
        self.source = source
    }

    public func start(host: String? = nil, onReady: @escaping @Sendable (URL) -> Void,
                      onFailure: @escaping @Sendable (Error) -> Void) {
        queue.async { [self] in
            guard !stopped, listener == nil else { return }
            guard let host = host ?? Self.wifiAddress() else {
                onFailure(URLError(.notConnectedToInternet)); return
            }
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 20
                configuration.timeoutIntervalForResource = 86_400
                configuration.httpMaximumConnectionsPerHost = 6
                configuration.urlCache = nil
                for cookie in HTTPCookieStorage.shared.cookies(for: source) ?? [] {
                    configuration.httpCookieStorage?.setCookie(cookie)
                }
                let delegateQueue = OperationQueue()
                delegateQueue.maxConcurrentOperationCount = 1
                delegateQueue.underlyingQueue = queue
                session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
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
                        var url = URLComponents()
                        url.scheme = "http"; url.host = host; url.port = Int(port.rawValue)
                        self.baseURL = url.url
                        do { onReady(try self.register(self.source)) } catch { onFailure(error) }
                    case .failed(let error): onFailure(error)
                    default: break
                    }
                }
                listener.start(queue: queue)
            } catch { onFailure(error) }
        }
    }

    public func stop() {
        queue.async { [self] in
            stopped = true
            listener?.cancel(); listener = nil
            for id in Array(clients.keys) { close(id) }
            session?.invalidateAndCancel(); session = nil
            resources.removeAll(); paths.removeAll(); baseURL = nil
        }
    }

    private func register(_ url: URL) throws -> URL {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let baseURL else { throw URLError(.badURL) }
        if let path = paths[url] {
            resources[path]?.accessed = Date()
            return baseURL.appendingPathComponent(path)
        }
        // Long-running live sessions cannot accumulate an unbounded segment map.
        if resources.count >= 16_384, let oldest = resources.min(by: { $0.value.accessed < $1.value.accessed }) {
            paths.removeValue(forKey: oldest.value.url); resources.removeValue(forKey: oldest.key)
        }
        let ext = url.pathExtension.lowercased()
        let suffix = ["m3u8", "mp4", "m4v", "mov", "ts", "m4s", "aac", "vtt", "key"].contains(ext) ? ext : "media"
        let path = "\(token)/\(UUID().uuidString).\(suffix)"
        resources[path] = Resource(url: url, accessed: Date()); paths[url] = path
        return baseURL.appendingPathComponent(path)
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
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, let client = self.clients[id] else { return }
            if Date().timeIntervalSince(client.activity) >= 30 { self.close(id) }
            else { self.expire(id) }
        }
    }

    private func receive(_ id: UUID, data: Data) {
        guard let client = clients[id], data.count < 8192 else { close(id); return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - data.count) { [weak self] bytes, _, complete, error in
            guard let self, !self.stopped, self.clients[id] != nil else { return }
            var received = data
            if let bytes { received.append(bytes) }
            if received.range(of: Data("\r\n\r\n".utf8)) != nil { self.request(id, data: received) }
            else if complete || error != nil || received.count >= 8192 { self.close(id) }
            else { self.receive(id, data: received) }
        }
    }

    private func request(_ id: UUID, data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { reject(id, status: 400); return }
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3, first[1].hasPrefix("/"),
              let resource = resources[String(first[1].dropFirst())] else { reject(id, status: 404); return }
        guard first[0] == "GET" || first[0] == "HEAD" else { reject(id, status: 405); return }
        resources[String(first[1].dropFirst())]?.accessed = Date()
        var request = URLRequest(url: resource.url)
        request.httpMethod = String(first[0])
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let ranges = lines.dropFirst().filter { $0.lowercased().hasPrefix("range:") }
        guard ranges.count <= 1 else { reject(id, status: 400); return }
        if let range = ranges.first { request.setValue(String(range.dropFirst(6)).trimmingCharacters(in: .whitespaces), forHTTPHeaderField: "Range") }
        // URL userinfo is valid input but must not become receiver-visible metadata.
        if var components = URLComponents(url: resource.url, resolvingAgainstBaseURL: false),
           let user = components.user, let password = components.password {
            request.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
            components.user = nil; components.password = nil; request.url = components.url
        }
        guard let task = session?.dataTask(with: request) else { reject(id, status: 503); return }
        clients[id]?.head = first[0] == "HEAD"
        clients[id]?.task = task; tasks[task.taskIdentifier] = id
        task.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let id = tasks[dataTask.taskIdentifier], let client = clients[id],
              let response = response as? HTTPURLResponse, !stopped else { completionHandler(.cancel); return }
        clients[id]?.response = response
        clients[id]?.activity = Date()
        guard (200...299).contains(response.statusCode) else {
            reject(id, status: response.statusCode); completionHandler(.cancel); return
        }
        if client.head {
            send(id, data: headers(response, head: true), finish: true)
            completionHandler(.cancel); return
        }
        let mime = response.mimeType?.lowercased() ?? ""
        if response.url?.pathExtension.lowercased() == "m3u8" || mime.contains("mpegurl") {
            guard response.expectedContentLength <= maximumManifestBytes else {
                reject(id, status: 502); completionHandler(.cancel); return
            }
            clients[id]?.manifest = Data()
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let id = tasks[dataTask.taskIdentifier], let client = clients[id], !stopped else { return }
        clients[id]?.activity = Date()
        if client.manifest != nil {
            guard (client.manifest?.count ?? 0) + data.count <= maximumManifestBytes else { reject(id, status: 502); return }
            clients[id]?.manifest?.append(data)
            return
        }
        if !client.headersSent {
            clients[id]?.prefix.append(data)
            guard let prefix = clients[id]?.prefix, prefix.count >= 64 else { return }
            clients[id]?.prefix = Data()
            if String(decoding: prefix.prefix(64), as: UTF8.self).contains("#EXTM3U") {
                guard prefix.count <= maximumManifestBytes else { reject(id, status: 502); return }
                clients[id]?.manifest = prefix
            } else { stream(id, data: prefix) }
        } else { stream(id, data: data) }
    }

    private func stream(_ id: UUID, data: Data) {
        guard let client = clients[id], !data.isEmpty else { return }
        guard let response = client.response, client.queuedBytes + data.count <= maximumBufferedBytes else { close(id); return }
        var chunk = Data()
        if !client.headersSent {
            chunk.append(headers(response)); clients[id]?.headersSent = true
        }
        chunk.append(Data("\(String(data.count, radix: 16))\r\n".utf8)); chunk.append(data); chunk.append(Data("\r\n".utf8))
        clients[id]?.chunks.append(chunk); clients[id]?.queuedBytes += chunk.count
        if !client.suspended, client.task?.state == .running { client.task?.suspend(); clients[id]?.suspended = true }
        drain(id)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = tasks[task.taskIdentifier], let initial = clients[id], !initial.head, !stopped else { return }
        if !initial.prefix.isEmpty {
            clients[id]?.prefix = Data()
            if String(decoding: initial.prefix, as: UTF8.self).contains("#EXTM3U") { clients[id]?.manifest = initial.prefix }
            else { stream(id, data: initial.prefix) }
        }
        guard let client = clients[id] else { return }
        guard error == nil, let response = client.response else {
            if client.headersSent { close(id) } else { reject(id, status: 502) }
            return
        }
        if let manifest = client.manifest {
            do {
                guard let base = response.url else { throw URLError(.badURL) }
                let body = try HLSRelayPlaylist.rewrite(manifest, relativeTo: base) { try register($0) }
                let header = "HTTP/1.1 200 OK\r\nContent-Type: application/vnd.apple.mpegurl\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                send(id, data: Data(header.utf8) + body, finish: true)
            } catch { reject(id, status: 502) }
            return
        }
        if !client.headersSent {
            let header = headers(response)
            clients[id]?.chunks.append(header); clients[id]?.queuedBytes += header.count; clients[id]?.headersSent = true
        }
        let end = Data("0\r\n\r\n".utf8)
        clients[id]?.chunks.append(end); clients[id]?.queuedBytes += end.count; clients[id]?.completed = true
        drain(id)
    }

    private func headers(_ response: HTTPURLResponse, head: Bool = false) -> Data {
        var result = "HTTP/1.1 \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))\r\nCache-Control: no-store\r\nConnection: close\r\n"
        for name in ["Content-Type", "Content-Range", "Accept-Ranges"] {
            if let value = response.value(forHTTPHeaderField: name), !value.contains("\r"), !value.contains("\n") { result += "\(name): \(value)\r\n" }
        }
        if head {
            // Rewriting a manifest changes its length. HEAD must not advertise
            // the provider's original size for the receiver's rewritten copy.
            if response.expectedContentLength >= 0, response.url?.pathExtension.lowercased() != "m3u8",
               response.mimeType?.lowercased().contains("mpegurl") != true {
                result += "Content-Length: \(response.expectedContentLength)\r\n"
            }
        } else { result += "Transfer-Encoding: chunked\r\n" }
        return Data((result + "\r\n").utf8)
    }

    private func drain(_ id: UUID) {
        guard let client = clients[id], !client.sending else { return }
        guard let chunk = client.chunks.first else {
            if client.completed { close(id) }
            else if client.suspended { clients[id]?.suspended = false; client.task?.resume() }
            return
        }
        clients[id]?.sending = true
        client.connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self, self.clients[id] != nil else { return }
            guard error == nil else { self.close(id); return }
            self.clients[id]?.chunks.removeFirst(); self.clients[id]?.queuedBytes -= chunk.count
            self.clients[id]?.sending = false; self.clients[id]?.activity = Date()
            self.drain(id)
        })
    }

    private func send(_ id: UUID, data: Data, finish: Bool) {
        clients[id]?.connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil || finish { self?.close(id) }
        })
    }

    private func reject(_ id: UUID, status: Int) {
        if let task = clients[id]?.task { tasks.removeValue(forKey: task.taskIdentifier); task.cancel() }
        send(id, data: Data("HTTP/1.1 \(status) Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), finish: true)
    }

    private func close(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        if let task = client.task { tasks.removeValue(forKey: task.taskIdentifier); task.cancel() }
        client.connection.cancel()
    }

    public static func wifiAddress() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var current = addresses
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.pointee.ifa_name).hasPrefix("en"),
                  (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
