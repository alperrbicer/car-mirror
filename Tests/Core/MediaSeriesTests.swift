import XCTest
@testable import MirrorCore

final class MediaSeriesTests: XCTestCase {
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
        XCTAssertEqual(MediaSeriesCatalog.playbackQueue(for: movie, in: [movie, live]), [movie, live])
    }
}
