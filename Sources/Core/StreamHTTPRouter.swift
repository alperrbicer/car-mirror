import Foundation

public struct StreamHTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public var wireData: Data {
        let reason = [200: "OK", 206: "Partial Content", 400: "Bad Request", 404: "Not Found",
                      405: "Method Not Allowed", 416: "Range Not Satisfiable", 503: "Service Unavailable"][status] ?? "Error"
        var fields = headers
        fields["Connection"] = "close"
        fields["Cache-Control"] = "no-store"
        fields["X-Content-Type-Options"] = "nosniff"
        let head = "HTTP/1.1 \(status) \(reason)\r\n" + fields.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)\r\n" }.joined() + "\r\n"
        return Data(head.utf8) + body
    }
}

/// Small, read-only HTTP surface: a random per-session path and three media routes.
public struct StreamHTTPRouter: Sendable {
    public let token: String
    public let buffer: HLSBuffer

    public init(token: String, buffer: HLSBuffer) {
        self.token = token
        self.buffer = buffer
    }

    public func respond(to request: Data) -> StreamHTTPResponse {
        guard request.count <= 8_192, let text = String(data: request, encoding: .utf8),
              text.contains("\r\n\r\n") else { return error(400) }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, ["HTTP/1.0", "HTTP/1.1"].contains(String(first[2])) else { return error(400) }
        let method = String(first[0])
        guard method == "GET" || method == "HEAD" else { return error(405) }
        let path = String(first[1])
        let prefix = "/\(token)/"
        guard path.hasPrefix(prefix) else { return error(404) }
        let name = String(path.dropFirst(prefix.count))
        guard !name.contains("/"), !name.contains("%"), !name.contains(".."), !name.contains("?") else { return error(404) }

        let content: Data
        let type: String
        if name == "stream.m3u8" {
            guard let playlist = buffer.playlist() else { return error(503) }
            content = playlist
            type = "application/vnd.apple.mpegurl"
        } else {
            guard let media = buffer.media(named: name) else { return error(404) }
            content = media
            type = "video/mp4"
        }

        var status = 200
        var body = content
        var headers = ["Content-Type": type, "Accept-Ranges": "bytes"]
        let rangeLines = lines.dropFirst().filter { $0.lowercased().hasPrefix("range:") }
        guard rangeLines.count <= 1 else { return error(400) }
        if let rangeLine = rangeLines.first {
            let value = String(rangeLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            guard let range = Self.parseRange(value, length: content.count) else {
                var response = error(416)
                response.headers["Content-Range"] = "bytes */\(content.count)"
                return response
            }
            status = 206
            body = content.subdata(in: range)
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(content.count)"
        }
        headers["Content-Length"] = String(body.count)
        return StreamHTTPResponse(status: status, headers: headers, body: method == "HEAD" ? Data() : body)
    }

    private func error(_ status: Int) -> StreamHTTPResponse {
        StreamHTTPResponse(status: status, headers: ["Content-Length": "0"], body: Data())
    }

    static func parseRange(_ value: String, length: Int) -> Range<Int>? {
        guard length > 0, value.hasPrefix("bytes="), !value.contains(",") else { return nil }
        let fields = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 2 else { return nil }
        if fields[0].isEmpty {
            guard let suffix = Int(fields[1]), suffix > 0 else { return nil }
            return max(0, length - suffix)..<length
        }
        guard let start = Int(fields[0]), start >= 0, start < length else { return nil }
        if fields[1].isEmpty { return start..<length }
        guard let end = Int(fields[1]), end >= start else { return nil }
        return start..<(min(end, length - 1) + 1)
    }
}
