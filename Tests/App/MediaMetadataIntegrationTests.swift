import XCTest
import CryptoKit
@testable import CarMirror

final class MediaMetadataIntegrationTests: XCTestCase {
    func testSeriesLookupValidatesEpisodeMembershipAndCachesCatalogAcrossEpisodes() async throws {
        let fixture = MetadataFixture()
        let loader = MediaMetadataLoader(fetch: { url, _ in try await fixture.fetch(url) })
        let secret = SourceSecret(url: URL(string: "https://playlist.example/library.m3u")!)
        func channel(_ id: Int) -> MediaChannel {
            MediaChannel(title: "Coast Stories EXXEN S01-E01", url: URL(string: "https://provider.example/series/u/p/\(id).mp4")!)
        }
        let first = try await loader.load(kind: .playlist, secret: secret, channel: channel(987))
        XCTAssertEqual(first?.summary, "General series synopsis")
        XCTAssertEqual(first?.duration, 1980)
        XCTAssertEqual(first?.genre, "Comedy")
        let second = try await loader.load(kind: .playlist, secret: secret, channel: channel(988))
        XCTAssertEqual(second?.summary, "Episode two synopsis")
        let series = try await loader.load(kind: .playlist, secret: secret, channel: channel(988), seriesOnly: true)
        XCTAssertEqual(series?.summary, "General series synopsis")
        let requests = await fixture.requests
        XCTAssertEqual(requests.filter { $0 == "get_series" }.count, 1)
        XCTAssertTrue(requests.contains("get_series_info:42"))
        XCTAssertFalse(requests.contains("get_series_info:987"))
        XCTAssertFalse(requests.contains("get_vod_info:987"))
    }

    func testMovieLookupFromOrdinaryM3UAndErrorsRemainDistinctFromMissingMetadata() async throws {
        let fixture = MetadataFixture()
        let loader = MediaMetadataLoader(fetch: { url, _ in try await fixture.fetch(url) })
        let secret = SourceSecret(url: URL(string: "https://playlist.example/library.m3u")!)
        func channel(_ id: Int) -> MediaChannel {
            MediaChannel(title: "Film", url: URL(string: "https://provider.example/movie/u/p/\(id).mp4")!)
        }
        let movie = try await loader.load(kind: .playlist, secret: secret, channel: channel(123))
        XCTAssertEqual(movie?.summary, "Film synopsis")
        do {
            _ = try await loader.load(kind: .playlist, secret: secret, channel: channel(404))
            XCTFail("A failed metadata request must not appear as missing provider metadata")
        } catch { XCTAssertTrue(error is URLError) }
        let unsupported = try await loader.load(kind: .stream, secret: secret, channel: channel(123))
        XCTAssertNil(unsupported)
    }

    func testResumeRecordsKeepArtworkAndDecodeRecordsWrittenBeforeMetadata() throws {
        let channel = MediaChannel(title: "Film", group: "Films", url: URL(string: "https://example.com/movie.mp4")!,
                                   metadata: MediaMetadata(artworkURL: URL(string: "https://example.com/poster.jpg"), summary: "A synopsis"))
        let record = LastPlaybackRecord(channel: channel, sourceID: UUID(), position: 60, duration: 600, isLive: false)
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(LastPlaybackRecord.self, from: data).channel, channel)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "metadata")
        let decoded = try JSONDecoder().decode(LastPlaybackRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.channel.metadata, MediaMetadata())
        XCTAssertEqual(decoded.url, channel.url)
        XCTAssertEqual(decoded.resumePosition, 60)
    }

    func testSeriesDisplayKeepsExistingContinuationIdentityAndPosition() throws {
        let sourceID = UUID()
        let record = LastPlaybackRecord(channel: MediaChannel(title: "Mahsun J EXXEN S01-E02",
            url: URL(string: "https://example.com/series/episode.mp4")!),
            sourceID: sourceID, position: 292, duration: 2028, isLive: false)
        let previousID = SHA256.hash(data: Data((sourceID.uuidString + "|series:mahsun j exxen").utf8))
            .map { String(format: "%02x", $0) }.joined()
        let restored = try JSONDecoder().decode(LastPlaybackRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(restored.id, previousID)
        XCTAssertEqual(restored.seriesTitle, "Mahsun J EXXEN")
        XCTAssertEqual(restored.episode?.season, 1)
        XCTAssertEqual(restored.episode?.number, 2)
        XCTAssertEqual(restored.resumePosition, 292)
        XCTAssertEqual(restored.progress, 292.0 / 2028.0)
    }
}

private actor MetadataFixture {
    private(set) var requests: [String] = []

    func fetch(_ url: URL) throws -> MediaMetadataLoader.Response {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let action = query.first(where: { $0.name == "action" })?.value ?? ""
        let id = query.first(where: { $0.name == "series_id" || $0.name == "vod_id" })?.value
        requests.append(action + (id.map { ":" + $0 } ?? ""))
        let json: String
        switch (action, id) {
        case ("get_series", _):
            json = #"[{"series_id":99,"name":"Coast Stories EXXEN","plot":"Wrong series"},{"series_id":42,"name":"Coast Stories","genre":"Comedy"}]"#
        case ("get_series_info", "99"):
            json = #"{"info":{"plot":"Wrong series"},"episodes":{"1":[{"id":111,"info":{"plot":"Wrong episode"}}]}}"#
        case ("get_series_info", "42"):
            json = #"{"info":{"plot":"General series synopsis"},"episodes":{"1":[{"id":"987","info":{"duration_secs":"1980"}},{"id":"988","info":{"plot":"Episode two synopsis"}}]}}"#
        case ("get_vod_info", "123"):
            json = #"{"info":{"description":"Film synopsis"}}"#
        default: throw URLError(.cannotConnectToHost)
        }
        return (Data(json.utf8), url)
    }
}
