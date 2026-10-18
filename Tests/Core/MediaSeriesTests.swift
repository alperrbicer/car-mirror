import XCTest
@testable import MirrorCore

final class MediaSeriesTests: XCTestCase {
    func testEpisodeDisplayNamePrefersProviderAndStripsOnlyEpisodeNotation() throws {
        let episode = try XCTUnwrap(MediaEpisode.parse("Akif S01-E03 - Playlist name"))
        XCTAssertEqual(episode.resolvedTitle(providerTitle: "<b>A New &amp; Different Day</b>"), "A New & Different Day")
        XCTAssertEqual(episode.resolvedTitle(providerTitle: "Akif S01-E03 - Yeni Başlangıç"), "Yeni Başlangıç")
        XCTAssertEqual(episode.resolvedTitle(providerTitle: "Akif - Yol Ayrımı"), "Yol Ayrımı")
        XCTAssertEqual(episode.resolvedTitle(providerTitle: "Akif Geri Dönüyor"), "Akif Geri Dönüyor")
        XCTAssertEqual(episode.resolvedTitle(providerTitle: "1984"), "1984")
        XCTAssertEqual(episode.resolvedTitle(providerTitle: nil), "Playlist name")
        XCTAssertEqual(episode.resolvedTitle(providerTitle: "null"), "Playlist name")
        XCTAssertEqual(episode.resolvedTitle(providerTitle: "Akif S01-E03"), "Playlist name")
    }

    func testMissingAndGenericEpisodeNamesUseNumberFallback() throws {
        let episode = try XCTUnwrap(MediaEpisode.parse("Akif S01-E03"))
        for title in [nil, "", "   ", "null", "N/A", "Akif", "Akif S01-E03", "S01-E03", "Episode 3", "3. bölüm",
                      "Bölüm 03", "Akif - 3. Bölüm", "03", "1x03", "1080p", "Akif S02E03 - Wrong season"] as [String?] {
            XCTAssertNil(episode.resolvedTitle(providerTitle: title), title ?? "nil")
        }
        let qualitySuffix = try XCTUnwrap(MediaEpisode.parse("Akif S01E03 1080p"))
        XCTAssertNil(qualitySuffix.resolvedTitle(providerTitle: nil))
    }

    private func posterChannel(_ title: String, _ id: Int, artwork: String?) -> MediaChannel {
        MediaChannel(title: title, url: URL(string: "https://example.com/series/user/pass/\(id).mp4")!,
                     metadata: MediaMetadata(artworkURL: artwork.flatMap(URL.init(string:))))
    }

    func testCategoryPreviewUsesDifferentSeriesDespiteEpisodePosterVariants() {
        let input = [posterChannel("Show S01-E01", 1, artwork: "https://art.example/show.jpg?episode=1"),
                     posterChannel("SHOW S01-E02", 2, artwork: "https://art.example/show.jpg?episode=2"),
                     posterChannel("Show S02-E01", 3, artwork: "https://art.example/season-two.jpg"),
                     posterChannel("Other S01-E01", 4, artwork: "https://art.example/other.jpg"),
                     posterChannel("Third S01-E01", 5, artwork: "https://art.example/third.jpg")]
        XCTAssertEqual(MediaChannelCategory.artworkPreview(input), [input[0], input[3], input[4]])
    }

    func testCategoryPreviewFindsArtworkAfterAnEpisodeWithoutAPosterAndSkipsRepeatedImages() {
        let input = [posterChannel("Show S01-E01", 1, artwork: nil),
                     posterChannel("Show S01-E02", 2, artwork: "https://art.example/shared.jpg"),
                     posterChannel("Other S01-E01", 3, artwork: "https://art.example/shared.jpg"),
                     posterChannel("Other S01-E02", 4, artwork: "https://art.example/other.jpg")]
        XCTAssertEqual(MediaChannelCategory.artworkPreview(input), [input[1], input[3]])
    }

    func testCategoryPreviewDoesNotRepeatASingleSeriesToFillThreeSlots() {
        let input = (1...3).map { posterChannel("Show S01-E0\($0)", $0, artwork: "https://art.example/\($0).jpg") }
        XCTAssertEqual(MediaChannelCategory.artworkPreview(input), [input[0]])
        XCTAssertTrue(MediaChannelCategory.artworkPreview([]).isEmpty)
    }

    func testCategoryPreviewWithoutArtworkStillUsesDifferentTitlesInProviderOrder() {
        let input = [posterChannel("Show S01-E01", 1, artwork: nil),
                     posterChannel("Show S01-E02", 2, artwork: nil),
                     posterChannel("Other", 3, artwork: nil),
                     posterChannel("  OTHER  ", 4, artwork: nil),
                     posterChannel("Third", 5, artwork: nil)]
        XCTAssertEqual(MediaChannelCategory.artworkPreview(input), [input[0], input[2], input[4]])
    }

    private func channel(_ title: String, _ id: Int, group: String = "DIZI: Exxen", route: String = "series", extension ext: String = "mp4") -> MediaChannel {
        MediaChannel(title: title, group: group, url: URL(string: "https://example.com/\(route)/user/pass/\(id).\(ext)")!)
    }

    func testExplicitProviderEpisodeFormatsAndEpisodeTitles() throws {
        for name in ["Mahsun J EXXEN S01-E02", "Mahsun J EXXEN s1e2", "Mahsun J EXXEN 1x02",
                     "Mahsun J EXXEN 1. Sezon 2. Bölüm", "Mahsun J EXXEN Sezon 1 Bölüm 2",
                     "Mahsun J EXXEN [S01.E02]"] {
            let episode = try XCTUnwrap(MediaEpisode.parse(name), name)
            XCTAssertEqual(episode.seriesTitle, "Mahsun J EXXEN")
            XCTAssertEqual(episode.season, 1); XCTAssertEqual(episode.number, 2)
            XCTAssertNil(episode.title)
        }
        let subtitled = try XCTUnwrap(MediaEpisode.parse("Kıyı Hikâyeleri S02-E10 - Yeni Başlangıç"))
        XCTAssertEqual(subtitled.title, "Yeni Başlangıç")
        XCTAssertEqual(subtitled.season, 2); XCTAssertEqual(subtitled.number, 10)
        XCTAssertEqual(MediaEpisode.parse("Dizi S00E01")?.season, 0)
    }

    func testNumbersYearsResolutionsAndMissingSeriesNamesStayUngrouped() {
        for title in ["S01-E01", "  S01-E01", "1983", "Film 2025", "Film 1080p", "TR: Spor 1", "Film S01E02abc", "Film S1234E01"] {
            XCTAssertNil(MediaEpisode.parse(title), title)
        }
    }

    func testSeriesAndSeasonsUseNumericOrderingWithoutLosingAlternateEpisodes() throws {
        let input = [channel("Kıyı Hikâyeleri S02-E01", 21), channel("Kıyı Hikâyeleri S01-E10", 10),
                     channel("Gece Vardiyası S01-E01", 51), channel("Kıyı Hikâyeleri S01-E02", 2),
                     channel("Kıyı Hikâyeleri S01-E01", 1), channel("Kıyı Hikâyeleri 1x02 - Alternatif", 202)]
        let catalog = MediaSeriesCatalog(input)
        XCTAssertEqual(catalog.series.map(\.title), ["Kıyı Hikâyeleri", "Gece Vardiyası"])
        let first = try XCTUnwrap(catalog.series.first)
        XCTAssertEqual(first.seasons.map(\.number), [1, 2])
        XCTAssertEqual(first.seasons[0].channels.map(\.episode?.number), [1, 2, 2, 10])
        XCTAssertEqual(first.channels.map(\.id), [input[4], input[3], input[5], input[1], input[0]].map(\.id))
        XCTAssertTrue(catalog.ungrouped.isEmpty)
    }

    func testGroupsDoNotMergeProvidersAndUnrecognizedContentRemainsAccessible() {
        let movie = channel("A Film", 1, group: "Film", route: "movie")
        let live = channel("Show S01-E01", 2, route: "live", extension: "m3u8")
        let audio = channel("Show S01-E01", 3, extension: "mp3")
        let unknown = channel("Provider special", 4)
        let first = channel("Show S01-E01", 5)
        let same = channel("SHOW S01-E02", 6)
        let other = channel("Show S01-E03", 7, group: "Other provider")
        let catalog = MediaSeriesCatalog([movie, live, audio, unknown, first, same, other])
        XCTAssertEqual(catalog.series.count, 2)
        XCTAssertEqual(catalog.series[0].channels, [first, same])
        XCTAssertEqual(catalog.ungrouped, [movie, live, audio, unknown])
        XCTAssertEqual(MediaSeriesCatalog.playbackQueue(for: same, in: [other, same, movie, first, live]), [first, same])
        XCTAssertEqual(MediaSeriesCatalog.playbackQueue(for: first, in: [movie]), [first])
        XCTAssertEqual(MediaSeriesCatalog.playbackQueue(for: movie, in: [movie, live]), [movie])
    }

    func testMovieQueueExcludesOtherCategoriesLiveAudioAndEpisodes() {
        let movie = channel("Movie", 1, group: "  Films ", route: "movie")
        let sameCategory = channel("Other film", 2, group: "Films", route: "movie")
        let otherCategory = channel("Other category", 3, group: "New", route: "movie")
        let episode = channel("Show S01E01", 4, group: "Films")
        let live = channel("Live", 5, group: "Films", route: "live")
        let audio = channel("Audio", 6, group: "Films", route: "movie", extension: "mp3")
        let input = [otherCategory, sameCategory, live, movie, episode, audio]
        XCTAssertEqual(MediaSeriesCatalog.playbackQueue(for: movie, in: input), [sameCategory, movie])
        XCTAssertEqual(MediaSeriesCatalog.playbackQueue(for: live, in: input), input)
        XCTAssertEqual(MediaSeriesCatalog.playbackQueue(for: movie, in: [otherCategory]), [movie])
        let uncategorized = channel("Uncategorized", 7, group: "", route: "movie")
        XCTAssertEqual(MediaSeriesCatalog.playbackQueue(for: uncategorized, in: input + [uncategorized]), [uncategorized])
    }

    func testLibrarySortUsesRealDatesAndPreservesOrderForMissingDatesAndEqualTitles() {
        let dates: [Int: Date] = [2: Date(timeIntervalSince1970: 200), 3: Date(timeIntervalSince1970: 300)]
        let names = [1: "Film 10", 2: "Film 2", 3: "Film 2", 4: "Film 1"]
        let items = [1, 2, 3, 4]
        XCTAssertEqual(MediaLibrarySort.provider.sorted(items, title: { names[$0]! }, addedAt: { dates[$0] }), items)
        XCTAssertEqual(MediaLibrarySort.recentlyAdded.sorted(items, title: { names[$0]! }, addedAt: { dates[$0] }), [3, 2, 1, 4])
        XCTAssertEqual(MediaLibrarySort.titleAscending.sorted(items, title: { names[$0]! }, addedAt: { dates[$0] }), [4, 2, 3, 1])
        XCTAssertEqual(MediaLibrarySort.titleDescending.sorted(items, title: { names[$0]! }, addedAt: { dates[$0] }), [1, 2, 3, 4])
    }

    func testPlaylistAndXtreamRecencyDoNotUseYearsOrStreamIDsAsDates() throws {
        let list = #"""
        #EXTM3U
        #EXTINF:-1 tvg-added="1700000000",Old release 1983
        https://example.com/movie/u/p/1.mp4
        #EXTINF:-1,New release 2026
        https://example.com/movie/u/p/99999.mp4
        """#
        let channels = try M3UParser.parse(Data(list.utf8), baseURL: URL(string: "https://example.com/list.m3u")!, fallbackTitle: "Test")
        XCTAssertEqual(channels[0].metadata.addedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(channels[1].metadata.addedAt)
        let catalog = Data(#"[{"stream_id":1,"added":"1700000000"},{"stream_id":"2","added":1700000010},{"stream_id":99999},{"stream_id":3,"added":"NaN"}]"#.utf8)
        XCTAssertEqual(try MediaCatalogRecency.parse(catalog), ["1": Date(timeIntervalSince1970: 1_700_000_000), "2": Date(timeIntervalSince1970: 1_700_000_010)])
        let legacy = Data(#"{"year":"2026"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(MediaMetadata.self, from: legacy).addedAt)
    }
}
