import XCTest
@testable import MirrorCore

final class MediaMetadataTests: XCTestCase {
    private let base = URL(string: "https://provider.example/list.m3u")!

    func testTurkishSeriesNamesMatchASCIIPlaylistTitles() throws {
        let catalog = try SeriesMetadataParser.catalog(Data(#"[{"series_id":339,"name":"Aşk Kumardır","plot":"A series synopsis"},{"series_id":340,"name":"Işıklar"},{"series_id":341,"name":"Another series"}]"#.utf8), baseURL: base)
        let url = URL(string: "https://provider.example/movie/u/p/987.mp4")!
        XCTAssertEqual(SeriesMetadataParser.candidates(in: catalog, for: MediaChannel(title: "Ask Kumardir S01-E01", url: url)).map(\.id), ["339"])
        XCTAssertEqual(SeriesMetadataParser.candidates(in: catalog, for: MediaChannel(title: "ISIKLAR S01-E01", url: url)).map(\.id), ["340"])
    }

    func testSpellingVariantsDiscoverCandidatesButStillRequireEpisodeMembership() throws {
        let catalog = try SeriesMetadataParser.catalog(Data(#"[{"series_id":1,"name":"Adım Başı Kafe"},{"series_id":2,"name":"Adim Basi Cafe"},{"series_id":3,"name":"Unrelated Show"}]"#.utf8), baseURL: base)
        let channel = MediaChannel(title: "Adim Basi Cafe S01-E01", url: URL(string: "https://provider.example/movie/u/p/987.mp4")!)
        XCTAssertEqual(SeriesMetadataParser.candidates(in: catalog, for: channel).map(\.id), ["2", "1"])
        let wrong = Data(#"{"info":{"plot":"Wrong series"},"episodes":{"1":[{"id":"111"}]}}"#.utf8)
        XCTAssertNil(try SeriesMetadataParser.parseInfo(wrong, episodeID: "987", baseURL: base))
        let correct = Data(#"{"info":{"plot":"Series synopsis"},"episodes":{"1":[{"id":"987","info":{"plot":"null","duration_secs":1860}}]}}"#.utf8)
        let metadata = try SeriesMetadataParser.parseInfo(correct, episodeID: "987", baseURL: base)
        XCTAssertEqual(metadata?.summary, "Series synopsis")
        XCTAssertEqual(metadata?.duration, 1860)
    }

    func testOptInSanitizedProviderDescriptions() throws {
        guard let path = ProcessInfo.processInfo.environment["MIRIVO_METADATA_OBSERVATIONS"] else { throw XCTSkip("No opt-in provider observations") }
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let rows = try XCTUnwrap(root["series"] as? [[String: Any]])
        let channels = try XCTUnwrap(root["channels"] as? [[String: String]])
        let catalog = try SeriesMetadataParser.catalog(JSONSerialization.data(withJSONObject: rows.map { ["series_id": $0["seriesID"]!, "name": $0["title"]!] }), baseURL: base)
        XCTAssertFalse(channels.isEmpty)
        for row in channels {
            let channel = MediaChannel(title: try XCTUnwrap(row["title"]), url: URL(string: "https://provider.example/movie/u/p/\(try XCTUnwrap(row["streamID"])).mkv")!)
            let candidate = try XCTUnwrap(SeriesMetadataParser.candidates(in: catalog, for: channel).first)
            let series = try XCTUnwrap(rows.first { String(describing: $0["seriesID"]!) == candidate.id })
            let info = try XCTUnwrap(series["info"] as? [String: Any])
            let expected = try XCTUnwrap(MediaMetadata(summary: info["plot"] as? String).summary)
            let episodes = try XCTUnwrap(series["episodes"] as? [[String: Any]])
            let payload = try JSONSerialization.data(withJSONObject: ["info": info, "episodes": ["1": episodes]])
            let metadata = try XCTUnwrap(SeriesMetadataParser.parseInfo(payload, episodeID: row["streamID"]!, baseURL: base))
            XCTAssertEqual(metadata.summary, expected)
            print("MIRIVO_PROVIDER_DESCRIPTION: \(channel.title), summaryCharacters=\(metadata.summary?.count ?? 0)")
        }
    }

    func testSeriesLookupRecognizesEpisodesExportedOnMovieRoutes() throws {
        let secret = SourceSecret(url: URL(string: "https://api.example/get.php?username=u&password=p&type=std_m3u&output=ts")!)
        let episode = MediaChannel(title: "Coast Stories EXXEN S01-E01", url: URL(string: "https://cdn.example/movie/u/p/987.mp4")!)
        let lookup = try XCTUnwrap(XtreamEndpoint.seriesLookup(kind: .playlist, secret: secret, channel: episode))
        XCTAssertEqual(lookup.catalogURL.host, "api.example")
        XCTAssertEqual(lookup.episodeID, "987")
        XCTAssertEqual(URLComponents(url: lookup.catalogURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "action" })?.value, "get_series")
        XCTAssertNotNil(try XtreamEndpoint.vodInfo(kind: .playlist, secret: secret, channel: episode), "The original VOD lookup remains available as a fallback")
        let movie = MediaChannel(title: "A film", url: episode.url)
        XCTAssertNil(try XtreamEndpoint.seriesLookup(kind: .playlist, secret: secret, channel: movie))
        let otherAccount = MediaChannel(title: episode.title, url: URL(string: "https://cdn.example/movie/other/p/987.mp4")!)
        XCTAssertNil(try XtreamEndpoint.seriesLookup(kind: .playlist, secret: secret, channel: otherAccount))
        XCTAssertNil(try XtreamEndpoint.seriesLookup(kind: .stream, secret: secret, channel: episode))
    }

    func testMovieSynopsisFallsBackAcrossResponseSectionsWithoutLosingInfoFields() throws {
        let data = Data(#"{"info":{"plot":"null","description":"<p> </p>","duration_secs":"7200","rating":"5.0"},"movie_data":{"stream_id":267,"description":"A film synopsis.","username":"must-not-be-retained","password":"must-not-be-retained"}}"#.utf8)
        let metadata = try VODMetadataParser.parse(data, baseURL: base)
        XCTAssertEqual(metadata.summary, "A film synopsis.")
        XCTAssertEqual(metadata.duration, 7200)
        XCTAssertEqual(metadata.rating, 5)
        let encoded = String(decoding: try JSONEncoder().encode(metadata), as: UTF8.self)
        XCTAssertFalse(encoded.contains("must-not-be-retained"))
        let preferred = try VODMetadataParser.parse(Data(#"{"info":{"plot":"Preferred synopsis"},"movie_data":{"description":"Fallback synopsis"}}"#.utf8), baseURL: base)
        XCTAssertEqual(preferred.summary, "Preferred synopsis")
    }

    func testEpisodeSynopsisReadsEpisodeFieldsAndKeepsSeriesSummarySeparate() throws {
        let data = Data(#"{"info":{"plot":"General series synopsis","genre":"Comedy"},"episodes":{"1":[{"id":"987","plot":"Episode synopsis","info":{"plot":"null","duration_secs":"2028","rating":"7.8"}},{"id":"988","description":"Another episode synopsis","info":{"plot":"Preferred episode synopsis"}}]}}"#.utf8)
        let episode = try XCTUnwrap(SeriesMetadataParser.parseInfo(data, episodeID: "987", baseURL: base))
        XCTAssertEqual(episode.summary, "Episode synopsis")
        XCTAssertEqual(episode.duration, 2028)
        XCTAssertEqual(episode.rating, 7.8)
        XCTAssertEqual(episode.genre, "Comedy")
        XCTAssertEqual(try SeriesMetadataParser.parseInfo(data, episodeID: "987", baseURL: base, includeEpisode: false)?.summary, "General series synopsis")
        XCTAssertEqual(try SeriesMetadataParser.parseInfo(data, episodeID: "988", baseURL: base)?.summary, "Preferred episode synopsis")
        XCTAssertNil(try SeriesMetadataParser.parseInfo(data, episodeID: "999", baseURL: base))
    }

    func testPlaylistEmptyDescriptionAliasDoesNotHideAnAvailableSynopsis() throws {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 tvg-description="null" description="<p> </p>" plot="A playlist synopsis.",Film
        https://provider.example/movie/u/p/123.mp4
        #EXTINF:-1 tvg-description=" " description="Another synopsis.",Another film
        https://provider.example/movie/u/p/124.mp4
        """
        let channels = try M3UParser.parse(Data(playlist.utf8), baseURL: base, fallbackTitle: "List")
        XCTAssertEqual(channels.map(\.metadata.summary), ["A playlist synopsis.", "Another synopsis."])
    }

    func testPlaylistRetainsArtworkDescriptionAndResetsMetadataForEveryEntry() throws {
        let playlist = """
        #EXTM3U
        #EXTINF:5400 tvg-logo="images/poster.jpg" description="A journey, across the sea." genre="Adventure" year="2025" rating="8.2" group-title="Films",The Voyage
        https://provider.example/movie/user/pass/123.mp4
        #EXTINF:-1 tvg-logo="file:///secret.png" description="Discard me",Invalid
        file:///invalid.mp4
        #EXTINF:-1,News
        https://provider.example/live/user/pass/4.m3u8
        #EXTINF:-1 tvg-logo="",Empty artwork
        https://provider.example/live/user/pass/5.m3u8
        """
        let channels = try M3UParser.parse(Data(playlist.utf8), baseURL: base, fallbackTitle: "List")
        XCTAssertEqual(channels.count, 3)
        XCTAssertEqual(channels[0].metadata.artworkURL?.absoluteString, "https://provider.example/images/poster.jpg")
        XCTAssertEqual(channels[0].metadata.summary, "A journey, across the sea.")
        XCTAssertEqual(channels[0].metadata.duration, 5400)
        XCTAssertEqual(channels[0].metadata.year, "2025")
        XCTAssertEqual(channels[0].metadata.rating, 8.2)
        XCTAssertEqual(channels[1].metadata, MediaMetadata())
        XCTAssertNil(channels[2].metadata.artworkURL)
        for unsafe in ["file:///tmp/image.png", "javascript:alert(1)", "https://user:pass@example.com/a.png", ""] {
            XCTAssertNil(MediaMetadata.artworkURL(unsafe, relativeTo: base))
        }
    }

    func testVODMetadataAcceptsProviderTypeVariationsAndBoundsContent() throws {
        let data = Data(#"{"info":{"movie_image":"/poster.jpg","plot":"<p>A film &amp; a journey.</p>","genre":"Drama","releasedate":"2024-03-12","duration_secs":"7200","rating":8.4,"director":"Director","cast":"Actor A, Actor B"},"movie_data":{"password":"must not be retained"}}"#.utf8)
        let metadata = try VODMetadataParser.parse(data, baseURL: base)
        XCTAssertEqual(metadata.artworkURL?.absoluteString, "https://provider.example/poster.jpg")
        XCTAssertEqual(metadata.summary, "A film & a journey.")
        XCTAssertEqual(metadata.year, "2024")
        XCTAssertEqual(metadata.duration, 7200)
        XCTAssertEqual(metadata.rating, 8.4)
        XCTAssertEqual(metadata.cast, "Actor A, Actor B")
        let encoded = try JSONEncoder().encode(metadata)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("password"))
        let sparse = try VODMetadataParser.parse(Data(#"{"info":{"plot":null,"duration":"01:32:10","rating":"unknown","releasedate":"0"}}"#.utf8), baseURL: base)
        XCTAssertEqual(sparse.duration, 5530)
        XCTAssertNil(sparse.summary); XCTAssertNil(sparse.rating); XCTAssertNil(sparse.year)
        XCTAssertEqual(MediaMetadata(summary: String(repeating: "x", count: 10_000)).summary?.count, 6_000)
        XCTAssertNil(MediaMetadata(duration: .infinity, rating: 50).duration)
        XCTAssertNil(MediaMetadata(duration: -1, rating: 50).rating)
        XCTAssertThrowsError(try VODMetadataParser.parse(Data(#"{"info":[]}"#.utf8), baseURL: base))
        XCTAssertThrowsError(try VODMetadataParser.parse(Data(repeating: 0, count: VODMetadataParser.maximumBytes + 1), baseURL: base))
    }

    func testVODLookupUsesOnlyKnownAccountMovieRoutesAndPreservesEncodedCredentials() throws {
        let secret = SourceSecret(url: URL(string: "https://provider.example/root/get.php?username=user%2Bname&password=p%26ss&type=m3u_plus&token=a%2Bb&vod_id=old")!)
        func channel(_ path: String) -> MediaChannel { MediaChannel(title: "Film", url: URL(string: "https://provider.example" + path)!) }
        let endpoint = try XCTUnwrap(XtreamEndpoint.vodInfo(kind: .playlist, secret: secret, channel: channel("/root/movie/user+name/p%26ss/123.mkv")))
        let components = try XCTUnwrap(URLComponents(url: endpoint, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/root/player_api.php")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "action" })?.value, "get_vod_info")
        XCTAssertEqual(components.queryItems?.filter { $0.name == "vod_id" }.map(\.value), ["123"])
        XCTAssertTrue(endpoint.absoluteString.contains("username=user%2Bname"))
        XCTAssertTrue(endpoint.absoluteString.contains("token=a%2Bb"))
        for path in ["/root/series/user+name/p%26ss/123.mkv", "/root/live/user+name/p%26ss/123.m3u8", "/movie/other/p%26ss/123.mp4", "/movie/user+name/p%26ss/not-a-number.mp4"] {
            XCTAssertNil(try XtreamEndpoint.vodInfo(kind: .playlist, secret: secret, channel: channel(path)))
        }
        XCTAssertNil(try XtreamEndpoint.vodInfo(kind: .stream, secret: secret, channel: channel("/movie/user+name/p%26ss/123.mp4")))
    }

    func testEnrichmentKeepsPlaylistFieldsWhenProviderReturnsSparseMetadata() {
        let original = MediaMetadata(artworkURL: base, summary: "Playlist summary", genre: "Drama")
        let merged = original.merging(MediaMetadata(year: "2025", director: "A director"))
        XCTAssertEqual(merged.artworkURL, base)
        XCTAssertEqual(merged.summary, "Playlist summary")
        XCTAssertEqual(merged.year, "2025")
        XCTAssertEqual(merged.director, "A director")
    }

    func testSingleQuotedAttributesAndTitleTextDoNotChangeArtworkMetadata() throws {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 TVG-LOGO = 'art/logo.png' group-title='News, Local',Channel tvg-logo="https://wrong.example/logo.png"
        https://provider.example/live.m3u8
        """
        let channel = try XCTUnwrap(M3UParser.parse(Data(playlist.utf8), baseURL: base, fallbackTitle: "List").first)
        XCTAssertEqual(channel.group, "News, Local")
        XCTAssertEqual(channel.metadata.artworkURL?.absoluteString, "https://provider.example/art/logo.png")
        let malformed = try VODMetadataParser.parse(Data(#"{"info":{"duration":"01:no:30"}}"#.utf8), baseURL: base)
        XCTAssertNil(malformed.duration)
    }

    func testOrdinaryM3ULooksUpMovieAndSeriesAccountsWithoutUsingEpisodeAsSeriesID() throws {
        let secret = SourceSecret(url: URL(string: "https://playlist.example/subscription.m3u?token=private")!)
        let channel = MediaChannel(title: "Coast Stories EXXEN S01-E01", url: URL(string: "https://provider.example/root/series/user+name/p%26ss/987.mp4")!)
        let lookup = try XCTUnwrap(XtreamEndpoint.seriesLookup(kind: .playlist, secret: secret, channel: channel))
        XCTAssertEqual(lookup.episodeID, "987")
        let catalog = try XCTUnwrap(URLComponents(url: lookup.catalogURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(catalog.host, "provider.example")
        XCTAssertEqual(catalog.path, "/root/player_api.php")
        XCTAssertEqual(catalog.queryItems?.first(where: { $0.name == "username" })?.value, "user+name")
        XCTAssertEqual(catalog.queryItems?.first(where: { $0.name == "password" })?.value, "p&ss")
        XCTAssertFalse(lookup.catalogURL.absoluteString.contains("private"))
        let info = try XCTUnwrap(URLComponents(url: XCTUnwrap(lookup.infoURL(seriesID: "42")), resolvingAgainstBaseURL: false))
        XCTAssertEqual(info.queryItems?.first(where: { $0.name == "series_id" })?.value, "42")
        XCTAssertNil(info.queryItems?.first(where: { $0.name == "vod_id" }))
        XCTAssertNil(lookup.infoURL(seriesID: "42&password=other"))
        XCTAssertNil(try XtreamEndpoint.seriesLookup(kind: .stream, secret: secret, channel: channel))

        let movie = MediaChannel(title: "Film", url: URL(string: "https://cdn.example/movie/user/pass/123.mp4")!)
        let saved = SourceSecret(url: URL(string: "https://api.example/get.php?username=user&password=pass&type=m3u_plus")!)
        XCTAssertEqual(try XtreamEndpoint.vodInfo(kind: .playlist, secret: secret, channel: movie)?.host, "cdn.example")
        XCTAssertEqual(try XtreamEndpoint.vodInfo(kind: .playlist, secret: saved, channel: movie)?.host, "api.example")
        let other = MediaChannel(title: "Film", url: URL(string: "https://cdn.example/movie/other/pass/123.mp4")!)
        XCTAssertNil(try XtreamEndpoint.vodInfo(kind: .playlist, secret: saved, channel: other))
    }

    func testSeriesSynopsisRequiresMatchingEpisodeAndPrefersEpisodeDescriptionWhenAvailable() throws {
        let data = Data(#"{"info":{"plot":"Series synopsis","releaseDate":"2024-01-01","genre":"Comedy"},"episodes":{"1":[{"id":"987","info":{"plot":null,"duration_secs":"1980"}},{"id":988,"info":{"description":"Episode two synopsis","rating":"8.5"}}]}}"#.utf8)
        let first = try XCTUnwrap(SeriesMetadataParser.parseInfo(data, episodeID: "987", baseURL: base))
        XCTAssertEqual(first.summary, "Series synopsis")
        XCTAssertEqual(first.year, "2024")
        XCTAssertEqual(first.duration, 1980)
        let second = try XCTUnwrap(SeriesMetadataParser.parseInfo(data, episodeID: "988", baseURL: base))
        XCTAssertEqual(second.summary, "Episode two synopsis")
        XCTAssertEqual(second.genre, "Comedy")
        XCTAssertEqual(second.rating, 8.5)
        XCTAssertEqual(try SeriesMetadataParser.parseInfo(data, episodeID: "988", baseURL: base, includeEpisode: false)?.summary, "Series synopsis")
        XCTAssertNil(try SeriesMetadataParser.parseInfo(data, episodeID: "not-in-this-series", baseURL: base))
        XCTAssertThrowsError(try SeriesMetadataParser.parseInfo(Data(#"{"user_info":{"auth":0}}"#.utf8), episodeID: "987", baseURL: base))
        XCTAssertThrowsError(try SeriesMetadataParser.parseInfo(Data(repeating: 0, count: SeriesMetadataParser.maximumInfoBytes + 1), episodeID: "987", baseURL: base))
    }

    func testSeriesCandidatesHandleProviderSuffixesWithoutAcceptingUnrelatedTitles() throws {
        let data = Data(#"[{"series_id":1,"name":"Coast Stories","plot":"Catalog synopsis"},{"series_id":"2","name":"COAST STORIES EXXEN"},{"series_id":3,"name":"An unrelated show"},{"series_id":"invalid","name":"Coast Stories EXXEN"}]"#.utf8)
        let catalog = try SeriesMetadataParser.catalog(data, baseURL: base)
        let channel = MediaChannel(title: "Coast Stories EXXEN S01-E01", url: URL(string: "https://provider.example/series/u/p/987.mp4")!)
        XCTAssertEqual(SeriesMetadataParser.candidates(in: catalog, for: channel).map(\.id), ["2", "1"])
        XCTAssertEqual(catalog.first?.metadata.summary, "Catalog synopsis")
        XCTAssertThrowsError(try SeriesMetadataParser.catalog(Data(#"{"user_info":{"auth":0}}"#.utf8), baseURL: base))
        XCTAssertThrowsError(try SeriesMetadataParser.catalog(Data(repeating: 0, count: SeriesMetadataParser.maximumCatalogBytes + 1), baseURL: base))
        let fallback = try VODMetadataParser.parse(Data(#"{"info":{"plot":"null","description":"Actual film synopsis"}}"#.utf8), baseURL: base)
        XCTAssertEqual(fallback.summary, "Actual film synopsis")
    }
}
