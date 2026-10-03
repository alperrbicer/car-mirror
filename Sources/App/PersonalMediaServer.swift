import Foundation
import Network
import Darwin
import UniformTypeIdentifiers

/// Serves one explicitly selected file, under an unguessable per-playback path.
/// Disk reads and network writes are bounded to 64 KiB; no directory browsing or URL proxying.
final class PersonalMediaServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Mirivo.PersonalMedia.HTTP", qos: .userInitiated)
    private let file: URL
    private let path: String
    private let size: Int64
    private let contentType: String
    private let cors = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, HEAD, OPTIONS\r\nAccess-Control-Allow-Headers: Range\r\nAccess-Control-Expose-Headers: Content-Length, Content-Range, Accept-Ranges\r\n"
    private var listener: NWListener?
    private var stopped = false
    private struct Client {
        let connection: NWConnection
        var handle: FileHandle?
        var activity = Date()
    }
    private var clients: [UUID: Client] = [:]

    init(file: URL) throws {
        guard file.isFileURL else { throw PersonalMediaError.unreadable }
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, let count = info.fileSize, count > 0 else { throw PersonalMediaError.unreadable }
        self.file = file
        size = Int64(count)
        path = "/\(UUID().uuidString)/media.\(file.pathExtension.lowercased())"
        contentType = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    func start(host: String? = nil, onReady: @escaping @Sendable (URL) -> Void,
               onFailure: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            guard !stopped, listener == nil else { return }
            guard let address = host ?? Self.wifiAddress() else { onFailure(); return }
            do {
                let parameters = NWParameters.tcp
                parameters.prohibitedInterfaceTypes = [.cellular]
                let listener = try NWListener(using: parameters, on: .any)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, !self.stopped else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port else { onFailure(); return }
                        var components = URLComponents()
                        components.scheme = "http"; components.host = address; components.port = Int(port.rawValue); components.path = self.path
                        if let url = components.url { onReady(url) } else { onFailure() }
                    case .failed: onFailure()
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] in self?.accept($0) }
                listener.start(queue: queue)
            } catch { onFailure() }
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            listener?.cancel(); listener = nil
            for id in Array(clients.keys) { close(id) }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped, clients.count < 6 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = Client(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state { case .failed, .cancelled: self?.close(id); default: break }
        }
        connection.start(queue: queue)
        expireIdleClient(id)
        receive(id, accumulated: Data())
    }

    private func expireIdleClient(_ id: UUID) {
        queue.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, let client = self.clients[id] else { return }
            if Date().timeIntervalSince(client.activity) >= 20 { self.close(id) }
            else { self.expireIdleClient(id) }
        }
    }

    private func receive(_ id: UUID, accumulated: Data) {
        guard let client = clients[id], accumulated.count < 8192 else { close(id); return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - accumulated.count) { [weak self] data, _, complete, error in
            guard let self, !self.stopped, self.clients[id] != nil else { return }
            var request = accumulated
            if let data { request.append(data) }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil { self.respond(id, request: request) }
            else if complete || error != nil || request.count >= 8192 { self.close(id) }
            else { self.receive(id, accumulated: request) }
        }
    }

    private func respond(_ id: UUID, request: Data) {
        guard let text = String(data: request, encoding: .utf8) else { reject(id, status: "400 Bad Request"); return }
        let lines = text.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3, first[1] == Substring(path) else { reject(id, status: "404 Not Found"); return }
        if first[0] == "OPTIONS" { reject(id, status: "204 No Content"); return }
        guard first[0] == "GET" || first[0] == "HEAD" else { reject(id, status: "405 Method Not Allowed"); return }
        let ranges = lines.dropFirst().compactMap { line -> String? in
            guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "range" else { return nil }
            return String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let range = ranges.first.flatMap { MediaByteRange.parse($0, size: size) }
        guard ranges.count <= 1, ranges.isEmpty || range != nil else {
            reject(id, status: "416 Range Not Satisfiable", extra: "Content-Range: bytes */\(size)\r\n"); return
        }
        let length = range?.length ?? size
        var headers = "HTTP/1.1 \(range == nil ? "200 OK" : "206 Partial Content")\r\nContent-Type: \(contentType)\r\nContent-Length: \(length)\r\nAccept-Ranges: bytes\r\nCache-Control: no-store\r\nConnection: close\r\n" + cors
        if let range { headers += "Content-Range: bytes \(range.start)-\(range.end)/\(size)\r\n" }
        if first[0] == "GET" {
            do {
                let handle = try FileHandle(forReadingFrom: file)
                clients[id]?.handle = handle
                try handle.seek(toOffset: UInt64(range?.start ?? 0))
            } catch { reject(id, status: "500 Internal Server Error"); return }
        }
        let isHead = first[0] == "HEAD"
        clients[id]?.connection.send(content: Data((headers + "\r\n").utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil || isHead { self.close(id) }
            else { self.sendBody(id, remaining: length) }
        })
    }

    private func sendBody(_ id: UUID, remaining: Int64) {
        guard !stopped, let client = clients[id], let handle = client.handle else { close(id); return }
        guard remaining > 0 else { close(id); return }
        do {
            guard let data = try handle.read(upToCount: Int(min(remaining, 65_536))), !data.isEmpty else { close(id); return }
            clients[id]?.activity = Date()
            client.connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.close(id) }
                else { self?.sendBody(id, remaining: remaining - Int64(data.count)) }
            })
        } catch { close(id) }
    }

    private func reject(_ id: UUID, status: String, extra: String = "") {
        let data = Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\n\(extra)\(cors)Connection: close\r\n\r\n".utf8)
        clients[id]?.connection.send(content: data, completion: .contentProcessed { [weak self] _ in self?.close(id) })
    }

    private func close(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        try? client.handle?.close()
        client.connection.cancel()
    }

    private static func wifiAddress() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return nil }
        defer { freeifaddrs(addresses) }
        var current = addresses
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.pointee.ifa_name).hasPrefix("en"),
                  entry.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
