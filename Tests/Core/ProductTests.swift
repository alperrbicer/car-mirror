import XCTest
@testable import MirrorCore

final class ProductTests: XCTestCase {
    func testPlaybackTimeDisplayHandlesHoursAndUnavailableTimes() {
        XCTAssertEqual(PlaybackTimeDisplay.timestamp(0), "00:00")
        XCTAssertEqual(PlaybackTimeDisplay.timestamp(65.9), "01:05")
        XCTAssertEqual(PlaybackTimeDisplay.timestamp(3_599), "59:59")
        XCTAssertEqual(PlaybackTimeDisplay.timestamp(3_661), "1:01:01")
        XCTAssertEqual(PlaybackTimeDisplay.timestamp(37_230), "10:20:30")
        for unavailable in [Double.nan, Double.infinity, -1, Double(Int.max)] {
            XCTAssertEqual(PlaybackTimeDisplay.timestamp(unavailable), "--:--")
        }
    }
    func testDailyViewingBudgetCountsPlaybackAndPersists() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var budget = DailyViewingBudget(now: start)
        budget.record(from: start, to: start.addingTimeInterval(600), playing: false)
        XCTAssertEqual(budget.remaining, 7200)
        budget.record(from: start, to: start.addingTimeInterval(3600), playing: true)
        let restored = try JSONDecoder().decode(DailyViewingBudget.self, from: JSONEncoder().encode(budget))
        XCTAssertEqual(restored.remaining, 3600)
        budget.record(from: start.addingTimeInterval(3600), to: start.addingTimeInterval(7300), playing: true)
        XCTAssertEqual(budget.remaining, 0)
    }
    func testDailyViewingBudgetSplitsMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        var budget = DailyViewingBudget(now: midnight.addingTimeInterval(-60), calendar: calendar, used: 7100)
        budget.record(from: midnight.addingTimeInterval(-30), to: midnight.addingTimeInterval(20), playing: true, calendar: calendar)
        XCTAssertEqual(budget.used, 20)
        budget.record(from: midnight.addingTimeInterval(20), to: midnight, playing: true, calendar: calendar)
        XCTAssertEqual(budget.used, 20)
    }

    func testSalesDisabledNeverLimitsFeatures() {
        let access = ProductAccess(salesEnabled: false, verifiedPro: false)
        XCTAssertTrue(access.fullAccess)
        XCTAssertNil(access.broadcastLimit)
        XCTAssertTrue(access.canAddSource(count: 900))
    }
    func testFreeAndVerifiedProHaveConsistentLimits() {
        let free = ProductAccess(salesEnabled: true, verifiedPro: false)
        XCTAssertTrue(free.canAddSource(count: 0))
        XCTAssertFalse(free.canAddSource(count: 1))
        XCTAssertEqual(free.broadcastLimit, 600)
        let pro = ProductAccess(salesEnabled: true, verifiedPro: true)
        XCTAssertTrue(pro.canAddSource(count: 50))
        XCTAssertNil(pro.broadcastLimit)
    }
    func testAudioTimelineFillsGapsAndNeverReplaysExpiredAudio() {
        var timeline = AudioTimeline()
        timeline.append(samples: [1, 1, 0.5, 0.5], at: 2)
        XCTAssertEqual(timeline.render(frameCount: 5), [0, 0, 0, 0, 1, 1, 0.5, 0.5, 0, 0])
        timeline.append(samples: [1, 1], at: 0)
        XCTAssertEqual(timeline.render(frameCount: 1), [0, 0])
        XCTAssertEqual(timeline.droppedFrames, 1)
    }
    func testAudioTimelineClipsPreOriginSamplesAndBoundsMemory() {
        var timeline = AudioTimeline()
        timeline.append(samples: [1, 1, 0.5, 0.5, 0.25, 0.25], at: -1)
        XCTAssertEqual(timeline.render(frameCount: 2), [0.5, 0.5, 0.25, 0.25])
        for i in 0..<200 { timeline.append(samples: Array(repeating: 1, count: 2048), at: Int64(2 + i * 1024)) }
        XCTAssertLessThanOrEqual(timeline.bufferedFrames, 96_000)
        XCTAssertGreaterThan(timeline.droppedFrames, 0)
    }
    func testM3UHandlesQuotedCommasGroupsRelativeAndDuplicateURLs() throws {
        let text = """
        #EXTM3U
        #EXTINF:-1 group-title="News, Live",Channel One
        streams/one.m3u8
        #EXTINF:-1,Duplicate
        streams/one.m3u8
        #EXTINF:-1,Channel Two
        #EXTGRP:Music
        https://media.example/two.m3u8
        #EXTINF:-1,Bad
        file:///etc/passwd
        """
        let channels = try M3UParser.parse(Data(text.utf8), baseURL: URL(string: "https://media.example/list.m3u")!, fallbackTitle: "List")
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].title, "Channel One")
        XCTAssertEqual(channels[0].group, "News, Live")
        XCTAssertEqual(channels[0].url.absoluteString, "https://media.example/streams/one.m3u8")
        XCTAssertEqual(channels[1].group, "Music")
    }
    func testHLSIsAChannelNotItsSegmentsAndInvalidSourcesAreRejected() throws {
        let url = URL(string: "https://media.example/live.m3u8")!
        let channels = try M3UParser.parse(Data("#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\n1.ts".utf8), baseURL: url, fallbackTitle: "Live")
        XCTAssertEqual(channels.map(\.url), [url])
        for invalid in ["file:///private/a", "javascript:alert(1)", "https://user:password@example.com/a", "https://example.com/a\nHeader: value"] {
            XCTAssertThrowsError(try MediaURL.validate(invalid))
        }
        XCTAssertThrowsError(try M3UParser.parse(Data("<html>login</html>".utf8), baseURL: url, fallbackTitle: "Invalid"))
        XCTAssertThrowsError(try M3UParser.parse(Data(repeating: 65, count: M3UParser.maximumBytes + 1), baseURL: url, fallbackTitle: "Large"))
    }
    func testXtreamM3URequestsHLSWithoutChangingEncodedCredentials() throws {
        for output in ["&output=ts", "&output=mpegts", ""] {
            let url = try XCTUnwrap(URL(string: "https://server.example:8080/prefix/get.php?username=a%2Bb&password=s%26e%3Dc%2Fret&type=m3u_plus&custom=x%2By" + output))
            let result = XtreamEndpoint.nativePlaylistURL(url)
            XCTAssertEqual(result.absoluteString, "https://server.example:8080/prefix/get.php?username=a%2Bb&password=s%26e%3Dc%2Fret&type=m3u_plus&custom=x%2By&output=m3u8")
        }
    }

    func testStandardM3UTransportStreamSourceRequestsProviderHLS() throws {
        let url = try XCTUnwrap(URL(string: "http://provider.example/get.php?username=user&password=secret&type=std_m3u&output=ts"))
        XCTAssertEqual(XtreamEndpoint.nativePlaylistURL(url).absoluteString,
                       "http://provider.example/get.php?username=user&password=secret&type=m3u_plus&output=m3u8")
    }

    func testNativePlaylistSelectionLeavesOtherProvidersAndChannelURLsUntouched() throws {
        for raw in [
            "https://server.example/list.m3u?output=ts",
            "https://server.example/live/user/pass/123.ts",
            "https://server.example/get.php?token=abc&output=ts",
            "https://server.example/get.php?username=u&password=p&type=m3u_plus&output=m3u8",
            "https://server.example/get.php?username=u&password=p&type=m3u_plus&output=custom",
            "https://server.example/get.php?username=u&password=p&type=m3u_plus&output=ts&output=m3u8"
        ] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertEqual(XtreamEndpoint.nativePlaylistURL(url), url)
        }
    }

    func testCategoryMetadataRequestAlsoUpgradesExistingHLSPlaylists() throws {
        let url = try XCTUnwrap(URL(string: "https://provider.example/get.php?username=u&password=p&type=std_m3u&output=m3u8"))
        XCTAssertEqual(XtreamEndpoint.nativePlaylistURL(url).absoluteString,
                       "https://provider.example/get.php?username=u&password=p&type=m3u_plus&output=m3u8")
    }

    func testPlaylistCategoriesKeepProviderOrderAndUncategorizedChannels() throws {
        let playlist = """
        #EXTM3U
        #EXTINF:-1 group-title=" Sports ",Sports One
        https://example.com/1.m3u8
        #EXTINF:-1 group-title="News",News One
        https://example.com/2.m3u8
        #EXTINF:-1,Sports Two
        #EXTGRP:Sports
        https://example.com/3.m3u8
        #EXTINF:-1,Other
        https://example.com/4.m3u8
        """
        let channels = try M3UParser.parse(Data(playlist.utf8), baseURL: URL(string: "https://example.com/list")!, fallbackTitle: "List")
        let groups = MediaChannelCategory.group(channels)
        XCTAssertEqual(groups.map(\.name), ["Sports", "News", ""])
        XCTAssertEqual(groups.map { $0.channels.map(\.title) }, [["Sports One", "Sports Two"], ["News One"], ["Other"]])
        XCTAssertTrue(MediaChannelCategory.group([]).isEmpty)
    }

    func testMediaEngineSelectionKeepsNativeHLSAndRoutesMatroskaToCompatibility() {
        let native = MediaChannel(title: "Live", url: URL(string: "https://example.com/live.m3u8")!)
        XCTAssertFalse(native.requiresCompatibilityPlayback)
        XCTAssertTrue(native.isLive)
        let episode = MediaChannel(title: "Episode", url: URL(string: "https://example.com/episode.MKV?token=example")!)
        XCTAssertTrue(episode.requiresCompatibilityPlayback)
        XCTAssertFalse(episode.isLive)
        let movie = MediaChannel(title: "Movie", url: URL(string: "https://example.com/movie.mp4")!)
        XCTAssertFalse(movie.requiresCompatibilityPlayback)
        XCTAssertFalse(movie.isLive)
    }

    func testXtreamCredentialsCannotInjectQueryParameters() throws {
        let secret = SourceSecret(url: URL(string: "https://server.example:8080")!, username: "a&password=other", password: "s+e?c/ret")
        let url = try XtreamEndpoint.playlist(secret: secret)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/get.php")
        XCTAssertEqual(components.queryItems?.first { $0.name == "username" }?.value, secret.username)
        XCTAssertEqual(components.queryItems?.filter { $0.name == "password" }.count, 1)
        XCTAssertEqual(components.queryItems?.first { $0.name == "password" }?.value, secret.password)
    }

    func testXtreamAcceptsServerOrEndpointAndEscapesPHPPlusCredentials() throws {
        for path in ["/prefix", "/prefix/", "/prefix/get.php", "/prefix/player_api.php"] {
            let url = URL(string: "https://server.example:8080\(path)?token=extra%2Btoken&action=ignored#fragment")!
            let playlist = try XtreamEndpoint.playlist(secret: SourceSecret(url: url, username: "a+b", password: "p+&ss"))
            let parts = try XCTUnwrap(URLComponents(url: playlist, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.path, "/prefix/get.php")
            XCTAssertEqual(parts.port, 8080)
            XCTAssertNil(parts.fragment)
            XCTAssertFalse(parts.percentEncodedQuery!.contains("+"), "PHP query parsing treats a literal plus as a space")
            XCTAssertEqual(parts.queryItems?.first { $0.name == "token" }?.value, "extra+token")
            XCTAssertEqual(parts.queryItems?.first { $0.name == "username" }?.value, "a+b")
            XCTAssertNil(parts.queryItems?.first { $0.name == "action" })
        }
        let pasted = SourceSecret(url: URL(string: "https://example.com/get.php?username=a%2Bb&password=p%2Bss&type=m3u")!)
        let parts = URLComponents(url: try XtreamEndpoint.playlist(secret: pasted), resolvingAgainstBaseURL: false)
        XCTAssertEqual(parts?.queryItems?.first { $0.name == "username" }?.value, "a+b")
        XCTAssertThrowsError(try XtreamEndpoint.playlist(secret: SourceSecret(url: URL(string: "https://example.com")!)))
        XCTAssertThrowsError(try XtreamEndpoint.playlist(secret: SourceSecret(url: URL(string: "file:///get.php")!, username: "a", password: "b")))
    }

    func testXtreamAccountEndpointSupportsCredentialsAndEncodedM3UWithoutActions() throws {
        let secret = SourceSecret(url: URL(string: "https://server.example:8080/prefix/")!, username: "a&user=other", password: "p+&=/secret")
        let url = try XCTUnwrap(XtreamEndpoint.accountInfo(kind: .xtream, secret: secret))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/prefix/player_api.php")
        XCTAssertEqual(components.queryItems?.map(\.name), ["username", "password"])
        XCTAssertEqual(components.queryItems?.first?.value, secret.username)
        XCTAssertEqual(components.queryItems?.last?.value, secret.password)
        let playlist = SourceSecret(url: URL(string: "http://server.example:8080/prefix/get.php?username=a%2Bb&password=s%26e%3Dc%2Fret&type=std_m3u&output=ts&token=x%2By&action=get_live_streams#fragment")!)
        XCTAssertEqual(try XtreamEndpoint.accountInfo(kind: .playlist, secret: playlist)?.absoluteString,
                       "http://server.example:8080/prefix/player_api.php?username=a%2Bb&password=s%26e%3Dc%2Fret&token=x%2By")
    }

    func testAccountEndpointDoesNotProbeOrdinaryPlaylistsOrAmbiguousCredentials() throws {
        for raw in ["https://example.com/list.m3u?username=u&password=p", "https://example.com/get.php?token=t",
                    "https://example.com/get.php?username=u&password=", "https://example.com/get.php?username=u&username=v&password=p"] {
            XCTAssertNil(try XtreamEndpoint.accountInfo(kind: .playlist, secret: SourceSecret(url: URL(string: raw)!)))
        }
        let secret = SourceSecret(url: URL(string: "https://example.com/get.php?username=u&password=p")!)
        XCTAssertNil(try XtreamEndpoint.accountInfo(kind: .stream, secret: secret))
    }

    func testIPTVExpiryAcceptsProviderTimestampFormatsAndIgnoresCredentials() throws {
        for timestamp in ["1800000000", "\"1800000000\"", "\" 1800000000 \""] {
            let data = Data("{\"user_info\":{\"auth\":\"1\",\"status\":\"Active\",\"exp_date\":\(timestamp),\"username\":\"private\",\"password\":\"secret\"}}".utf8)
            let info = try IPTVAccountInfo.parse(data)
            XCTAssertEqual(info.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
            XCTAssertFalse(info.isExpired(at: Date(timeIntervalSince1970: 1_799_999_999)))
            XCTAssertTrue(info.isExpired(at: Date(timeIntervalSince1970: 1_800_000_000)))
            let persisted = String(decoding: try JSONEncoder().encode(info), as: UTF8.self)
            XCTAssertFalse(persisted.contains("private")); XCTAssertFalse(persisted.contains("secret"))
        }
        let expired = try IPTVAccountInfo.parse(Data(#"{"user_info":{"auth":1,"status":"Expired","exp_date":null}}"#.utf8))
        XCTAssertTrue(expired.isExpired(at: .distantPast))
    }

    func testIPTVExpiryDoesNotInventUnlimitedDatesOrAcceptRejectedAccounts() throws {
        for value in ["null", "0", "\"0\"", "\"\"", "-1", "true", "\"invalid\"", "\"NaN\"", "\"Infinity\"", "1800000000000"] {
            let info = try IPTVAccountInfo.parse(Data("{\"user_info\":{\"auth\":1,\"exp_date\":\(value)}}".utf8))
            XCTAssertNil(info.expiresAt)
            XCTAssertFalse(info.providerReportsExpired)
        }
        XCTAssertNil(try IPTVAccountInfo.parse(Data(#"{"user_info":{"auth":1}}"#.utf8)).expiresAt)
        for response in [#"{"user_info":{"auth":0,"exp_date":"1800000000"}}"#,
                         #"{"user_info":{"auth":true,"exp_date":"1800000000"}}"#, #"{"user_info":{}}"#, #"{}"#, "<html>error</html>"] {
            XCTAssertThrowsError(try IPTVAccountInfo.parse(Data(response.utf8)))
        }
    }
}
