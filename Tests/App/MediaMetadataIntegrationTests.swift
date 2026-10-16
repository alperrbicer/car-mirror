import XCTest
import CryptoKit
@testable import CarMirror

final class MediaMetadataIntegrationTests: XCTestCase {
    func testCafeSpellingVariantLoadsVerifiedSeriesSynopsis() async throws {
        let loader = MediaMetadataLoader(fetch: { url, _ in
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let action = query.first { $0.name == "action" }?.value
            let id = query.first { $0.name == "series_id" }?.value
            let body: String
            switch (action, id) {
            case ("get_series", _):
                body = #"[{"series_id":1,"name":"Adim Basi Cafe","plot":"Wrong series"},{"series_id":2,"name":"Adım Başı Kafe"}]"#
            case ("get_series_info", "1"):
                body = #"{"info":{"plot":"Wrong series"},"episodes":{"1":[{"id":"111"}]}}"#
            case ("get_series_info", "2"):
                body = #"{"info":{"plot":"Series synopsis"},"episodes":{"1":[{"id":"987","info":{"plot":"null","duration_secs":1860,"rating":8}}]}}"#
            default: throw URLError(.badURL)
            }
            return (Data(body.utf8), url)
        })
        let channel = MediaChannel(title: "Adim Basi Cafe S01-E01", url: URL(string: "https://provider.example/movie/u/p/987.mkv")!)
        let secret = SourceSecret(url: URL(string: "https://playlist.example/list.m3u")!)
        for seriesOnly in [false, true] {
            let metadata = try await loader.load(kind: .playlist, secret: secret, channel: channel, seriesOnly: seriesOnly)
            XCTAssertEqual(metadata?.summary, "Series synopsis")
            if !seriesOnly {
                XCTAssertEqual(metadata?.duration, 1860)
                XCTAssertEqual(metadata?.rating, 8)
            }
        }
    }

    func testASCIIPlaylistEpisodeLoadsTurkishProviderSynopsis() async throws {
        let loader = MediaMetadataLoader(fetch: { url, _ in
            let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value
            let body: String
            switch action {
            case "get_series": body = #"[{"series_id":339,"name":"Aşk Kumardır"}]"#
            case "get_series_info": body = #"{"info":{"plot":"Provider series synopsis"},"episodes":{"1":[{"id":"987","info":{"duration_secs":1533}}]}}"#
            default: throw URLError(.badURL)
            }
            return (Data(body.utf8), url)
        })
        let channel = MediaChannel(title: "Ask Kumardir S01-E01", url: URL(string: "https://provider.example/movie/u/p/987.mkv")!)
        let metadata = try await loader.load(kind: .playlist, secret: SourceSecret(url: URL(string: "https://playlist.example/list.m3u")!), channel: channel)
        XCTAssertEqual(metadata?.summary, "Provider series synopsis")
        XCTAssertEqual(metadata?.duration, 1533)
    }
    func testSeriesEpisodeExportedAsMovieUsesOnlySeriesWithTheSameEpisodeID() async throws {
        let fixture = MetadataFixture()
        let loader = MediaMetadataLoader(fetch: { url, _ in try await fixture.fetch(url) })
        let secret = SourceSecret(url: URL(string: "https://playlist.example/library.m3u")!)
        let channel = MediaChannel(title: "Coast Stories EXXEN S01-E01", url: URL(string: "https://provider.example/movie/u/p/987.mp4")!)
        let metadata = try await loader.load(kind: .playlist, secret: secret, channel: channel)
        XCTAssertEqual(metadata?.summary, "General series synopsis")
        XCTAssertEqual(metadata?.duration, 1980)
        XCTAssertEqual(metadata?.genre, "Comedy")
        let requests = await fixture.requests
        XCTAssertTrue(requests.contains("get_series_info:99"))
        XCTAssertTrue(requests.contains("get_series_info:42"))
        XCTAssertFalse(requests.contains("get_vod_info:987"))
    }

    func testMovieEpisodeWithNoVerifiedSeriesKeepsItsOwnVODMetadata() async throws {
        let fixture = MetadataFixture()
        let loader = MediaMetadataLoader(fetch: { url, _ in try await fixture.fetch(url) })
        let channel = MediaChannel(title: "Coast Stories EXXEN S01-E03", url: URL(string: "https://provider.example/movie/u/p/125.mp4")!)
        let metadata = try await loader.load(kind: .playlist,
            secret: SourceSecret(url: URL(string: "https://playlist.example/library.m3u")!), channel: channel)
        XCTAssertEqual(metadata?.summary, "Film fallback synopsis")
        XCTAssertEqual(metadata?.rating, 5)
        let requests = await fixture.requests
        XCTAssertTrue(requests.contains("get_vod_info:125"))
    }

    func testMovieEpisodeCanUseVODWhenTheSeriesCatalogIsUnavailable() async throws {
        let fixture = MetadataFixture()
        let loader = MediaMetadataLoader(fetch: { url, _ in
            let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value
            if action == "get_series" { throw URLError(.cannotConnectToHost) }
            return try await fixture.fetch(url)
        })
        let secret = SourceSecret(url: URL(string: "https://playlist.example/library.m3u")!)
        let channel = MediaChannel(title: "Coast Stories EXXEN S01-E03", url: URL(string: "https://provider.example/movie/u/p/125.mp4")!)
        let metadata = try await loader.load(kind: .playlist, secret: secret, channel: channel)
        XCTAssertEqual(metadata?.summary, "Film fallback synopsis")
        let series = MediaChannel(title: channel.title, url: URL(string: "https://provider.example/series/u/p/987.mp4")!)
        do {
            _ = try await loader.load(kind: .playlist, secret: secret, channel: series)
            XCTFail("A failed series-only request must remain retryable")
        } catch { XCTAssertTrue(error is URLError) }
    }

    func testMovieEpisodeDoesNotTreatSeriesNetworkFailureAsMissingSynopsis() async throws {
        let loader = MediaMetadataLoader(fetch: { url, _ in
            let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value
            if action == "get_series" { throw URLError(.cannotConnectToHost) }
            return (Data(#"{"info":{"duration_secs":"1980","rating":"7.8"}}"#.utf8), url)
        })
        let secret = SourceSecret(url: URL(string: "https://playlist.example/library.m3u")!)
        let episode = MediaChannel(title: "Coast Stories S01-E01", url: URL(string: "https://provider.example/movie/u/p/126.mp4")!)
        do {
            _ = try await loader.load(kind: .playlist, secret: secret, channel: episode)
            XCTFail("A failed series lookup must offer retry when VOD has no synopsis")
        } catch { XCTAssertTrue(error is URLError) }
        let movie = MediaChannel(title: "Film", url: episode.url)
        let metadata = try await loader.load(kind: .playlist, secret: secret, channel: movie)
        XCTAssertNil(metadata?.summary)
        XCTAssertEqual(metadata?.duration, 1980, "An ordinary movie without a provider synopsis is still a valid response")
    }

    func testOptInProviderMetadata() async throws {
        struct Probe: Decodable {
            struct Item: Decodable { let title: String; let url: URL; let summaryLength: Int? }
            let source: SourceSecret
            let items: [Item]
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mirivo-provider-metadata.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("No opt-in provider metadata fixture") }
        let probe = try JSONDecoder().decode(Probe.self, from: Data(contentsOf: file))
        let loader = MediaMetadataLoader()
        for item in probe.items {
            do {
                let channel = MediaChannel(title: item.title, url: item.url)
                let metadata = try await loader.load(kind: .playlist, secret: probe.source, channel: channel)
                XCTAssertNotNil(metadata)
                XCTAssertEqual(metadata?.summary?.count, item.summaryLength, item.title)
                XCTAssertNotNil(metadata?.duration, item.title)
                XCTAssertNotNil(metadata?.rating, item.title)
                if channel.episode != nil {
                    let series = try await loader.load(kind: .playlist, secret: probe.source, channel: channel, seriesOnly: true)
                    XCTAssertEqual(series?.summary?.count, item.summaryLength, item.title)
                }
                print("MIRIVO_PROVIDER_METADATA: \(item.title), summaryCharacters=\(metadata?.summary?.count ?? 0)")
            } catch {
                // NSError's full description can include a credential-bearing URL.
                let failure = error as NSError
                XCTFail("Provider metadata request failed: \(failure.domain) [\(failure.code)]")
            }
        }
    }

    func testMovieSynopsisOutsideInfoKeepsDurationAndRatingFromInfo() async throws {
        let fixture = MetadataFixture()
        let loader = MediaMetadataLoader(fetch: { url, _ in try await fixture.fetch(url) })
        let channel = MediaChannel(title: "Film", url: URL(string: "https://provider.example/movie/u/p/125.mp4")!)
        let metadata = try await loader.load(kind: .playlist,
            secret: SourceSecret(url: URL(string: "https://playlist.example/library.m3u")!), channel: channel)
        XCTAssertEqual(metadata?.summary, "Film fallback synopsis")
        XCTAssertEqual(metadata?.duration, 7196)
        XCTAssertEqual(metadata?.rating, 5)
    }

    func testEpisodeSynopsisOutsideInfoDoesNotReplaceTheSeriesSynopsis() async throws {
        let fixture = MetadataFixture()
        let loader = MediaMetadataLoader(fetch: { url, _ in try await fixture.fetch(url) })
        let secret = SourceSecret(url: URL(string: "https://playlist.example/library.m3u")!)
        let channel = MediaChannel(title: "Coast Stories EXXEN S01-E03", url: URL(string: "https://provider.example/series/u/p/989.mp4")!)
        let episode = try await loader.load(kind: .playlist, secret: secret, channel: channel)
        XCTAssertEqual(episode?.summary, "Episode three synopsis")
        XCTAssertEqual(episode?.duration, 2028)
        XCTAssertEqual(episode?.rating, 7.8)
        let series = try await loader.load(kind: .playlist, secret: secret, channel: channel, seriesOnly: true)
        XCTAssertEqual(series?.summary, "General series synopsis")
    }

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
            json = #"{"info":{"plot":"General series synopsis"},"episodes":{"1":[{"id":"987","info":{"duration_secs":"1980"}},{"id":"988","info":{"plot":"Episode two synopsis"}},{"id":"989","description":"Episode three synopsis","info":{"plot":"null","duration_secs":"2028","rating":"7.8"}}]}}"#
        case ("get_vod_info", "123"):
            json = #"{"info":{"description":"Film synopsis"}}"#
        case ("get_vod_info", "125"):
            json = #"{"info":{"plot":"null","duration_secs":"7196","rating":"5.0"},"movie_data":{"description":"Film fallback synopsis"}}"#
        default: throw URLError(.cannotConnectToHost)
        }
        return (Data(json.utf8), url)
    }
}
