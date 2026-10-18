import Foundation
import Network
import Darwin
#if SWIFT_PACKAGE
import MirrorCore
#endif

/// Lives in the broadcast extension, so switching to YouTube does not suspend it.
public final class LocalStreamServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CarMirror.HTTP", qos: .userInitiated)
    private let router: StreamHTTPRouter
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var streamingClients: Set<UUID> = []
    private var bufferObserver: UUID?
    private var waitingClients: [UUID: (deadline: DispatchWorkItem, resume: @Sendable () -> Void)] = [:]
    private var stopped = false
    public let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        + UUID().uuidString.replacingOccurrences(of: "-", with: "")

    public init(buffer: HLSBuffer) {
        router = StreamHTTPRouter(token: token, buffer: buffer)
    }

    public func start(onReady: @escaping (UInt16) -> Void, onFailure: @escaping (Error) -> Void) {
        queue.async { [self] in
            guard !stopped, listener == nil else { return }
            bufferObserver = router.buffer.observeChanges { [weak self] in
                self?.queue.async { [weak self] in self?.wakeReaders() }
            }
            do {
                let parameters = NWParameters.tcp
                parameters.prohibitedInterfaceTypes = [.cellular]
                let listener = try NWListener(using: parameters, on: .any)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, !self.stopped else { return }
                    switch state {
                    case .ready:
                        if let port = listener?.port { onReady(port.rawValue) }
                    case .failed(let error): onFailure(error)
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: queue)
            } catch { onFailure(error) }
        }
    }

    public func url(host: String, port: UInt16) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/\(token)/stream.m3u8"
        return components.url!
    }

    public func localStreamURL(port: UInt16) -> URL {
        url(host: "127.0.0.1", port: port).deletingLastPathComponent().appendingPathComponent("live.mp4")
    }

    public func stop() {
        queue.async { [self] in
            stopped = true
            if let bufferObserver { router.buffer.removeObserver(bufferObserver) }
            bufferObserver = nil
            waitingClients.values.forEach { $0.deadline.cancel() }
            waitingClients.removeAll()
            listener?.cancel()
            listener = nil
            clients.values.forEach { $0.cancel() }
            clients.removeAll()
            streamingClients.removeAll()
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped, clients.count < 12 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close(id)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(id: id, accumulated: Data())
        queue.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, !self.streamingClients.contains(id) else { return }
            self.close(id)
        }
    }

    private func receive(id: UUID, accumulated: Data) {
        guard let connection = clients[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192 - accumulated.count) {
            [weak self] data, _, complete, error in
            guard let self, !self.stopped, self.clients[id] != nil else { return }
            var request = accumulated
            if let data { request.append(data) }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                if self.beginLocalStream(request, id: id) { return }
                let response = self.router.respond(to: request)
                connection.send(content: response.wireData, completion: .contentProcessed { [weak self] _ in
                    self?.close(id)
                })
            } else if complete || error != nil || request.count >= 8_192 {
                self.close(id)
            } else {
                self.receive(id: id, accumulated: request)
            }
        }
    }

    private func close(_ id: UUID) {
        waitingClients.removeValue(forKey: id)?.deadline.cancel()
        streamingClients.remove(id)
        clients.removeValue(forKey: id)?.cancel()
    }

    /// App-owned screens consume fragments immediately over loopback. HLS stays
    /// available for Cast/AirPlay receivers that load the playlist themselves.
    private func beginLocalStream(_ request: Data, id: UUID) -> Bool {
        guard let connection = clients[id],
              case let .hostPort(host, _) = connection.endpoint,
              host == NWEndpoint.Host("127.0.0.1") || host == NWEndpoint.Host("::1"),
              let line = String(data: request, encoding: .utf8)?.components(separatedBy: "\r\n").first,
              line == "GET /\(token)/live.mp4 HTTP/1.1" || line == "GET /\(token)/live.mp4 HTTP/1.0" else { return false }
        streamingClients.insert(id)
        startFragments(id: id, waitingSince: Date())
        return true
    }

    private func startFragments(id: UUID, waitingSince: Date) {
        guard !stopped, streamingClients.contains(id) else { return }
        let snapshot = router.buffer.snapshot()
        guard let initialization = snapshot.initialization, let latest = snapshot.segments.last else {
            // Rotation briefly replaces the init segment. Keep this valid
            // reader waiting for the new keyframe instead of returning 404.
            guard Date().timeIntervalSince(waitingSince) < 3 else { close(id); return }
            waitForFragment(id: id, timeout: 3 - Date().timeIntervalSince(waitingSince)) { [weak self] in
                self?.startFragments(id: id, waitingSince: waitingSince)
            }
            return
        }
        let header = Data("HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        sendStream(header + initialization + latest.data, id: id) { [weak self] in
            self?.sendNextFragment(id: id, sequence: latest.sequence + 1, generation: snapshot.generation, waitingSince: Date())
        }
    }

    private func sendNextFragment(id: UUID, sequence: Int, generation: Int, waitingSince: Date) {
        guard !stopped, streamingClients.contains(id) else { return }
        let snapshot = router.buffer.snapshot()
        guard snapshot.generation == generation, snapshot.initialization != nil else { close(id); return }
        guard (snapshot.segments.last?.sequence ?? sequence) - sequence <= 4 else { close(id); return }
        if let fragment = snapshot.segments.first(where: { $0.sequence == sequence }) {
            sendStream(fragment.data, id: id) { [weak self] in
                self?.sendNextFragment(id: id, sequence: sequence + 1, generation: generation, waitingSince: Date())
            }
        } else if (snapshot.segments.first?.sequence ?? sequence) > sequence || Date().timeIntervalSince(waitingSince) > 4 {
            // A slow/stalled reader must reconnect at the live edge instead of
            // accumulating seconds of stale screen data or unbounded buffers.
            close(id)
        } else {
            waitForFragment(id: id, timeout: 4 - Date().timeIntervalSince(waitingSince)) { [weak self] in
                self?.sendNextFragment(id: id, sequence: sequence, generation: generation, waitingSince: waitingSince)
            }
        }
    }

    private func waitForFragment(id: UUID, timeout: TimeInterval, resume: @escaping @Sendable () -> Void) {
        waitingClients.removeValue(forKey: id)?.deadline.cancel()
        let deadline = DispatchWorkItem { [weak self] in self?.close(id) }
        waitingClients[id] = (deadline, resume)
        queue.asyncAfter(deadline: .now() + max(0, timeout), execute: deadline)
    }

    private func wakeReaders() {
        guard !stopped else { return }
        let waiting = waitingClients
        waitingClients.removeAll(keepingCapacity: true)
        for (_, reader) in waiting {
            reader.deadline.cancel()
            reader.resume()
        }
    }

    private func sendStream(_ data: Data, id: UUID, completion: @escaping @Sendable () -> Void) {
        guard let connection = clients[id] else { return }
        // One outstanding fragment per client, with a bounded send deadline.
        let deadline = DispatchWorkItem { [weak self] in self?.close(id) }
        queue.asyncAfter(deadline: .now() + 2, execute: deadline)
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            deadline.cancel()
            guard let self, self.clients[id] != nil else { return }
            if error != nil { self.close(id) } else { completion() }
        })
    }

    /// Best-effort LAN address. Loopback remains available without Wi-Fi.
    public static func wifiAddress() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var current = addresses
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
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
