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
    private var stopped = false
    public let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        + UUID().uuidString.replacingOccurrences(of: "-", with: "")

    public init(buffer: HLSBuffer) {
        router = StreamHTTPRouter(token: token, buffer: buffer)
    }

    public func start(onReady: @escaping (UInt16) -> Void, onFailure: @escaping (Error) -> Void) {
        queue.async { [self] in
            guard !stopped, listener == nil else { return }
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

    public func stop() {
        queue.async { [self] in
            stopped = true
            listener?.cancel()
            listener = nil
            clients.values.forEach { $0.cancel() }
            clients.removeAll()
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
        queue.asyncAfter(deadline: .now() + 8) { [weak self] in self?.close(id) }
    }

    private func receive(id: UUID, accumulated: Data) {
        guard let connection = clients[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192 - accumulated.count) {
            [weak self] data, _, complete, error in
            guard let self, !self.stopped, self.clients[id] != nil else { return }
            var request = accumulated
            if let data { request.append(data) }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
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
        clients.removeValue(forKey: id)?.cancel()
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
