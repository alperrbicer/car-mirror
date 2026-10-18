import Foundation

/// Build with: xcrun swiftc -O Sources/Core/*.swift scripts/benchmark_catalog.swift -o build/catalog-benchmark
@main
struct CatalogBenchmark {
    static func main() throws {
        var results: [[String: Any]] = []
        for count in [1_000, 10_000, 20_000] {
            func makeChannels() -> [MediaChannel] {
                (0..<count).map { index in
                    let route = index % 3 == 0 ? "live" : index % 3 == 1 ? "movie" : "series"
                    return MediaChannel(title: route == "series" ? "Show \(index / 60) S01-E\(index % 20 + 1)" : "Title \(index)",
                                        group: "Category \(index % 12)",
                                        url: URL(string: "https://example.invalid/\(route)/user/password/\(index).m3u8")!)
                }
            }
            let channels = makeChannels()
            var checksum = 0
            func sample(_ name: String, _ operation: () -> Void) {
                operation()
                var times: [Double] = []
                for _ in 0..<9 {
                    let start = ProcessInfo.processInfo.systemUptime
                    operation()
                    times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                }
                times.sort()
                results.append(["channels": count, "operation": name, "median_ms": times[4], "p95_ms": times[8]])
            }
            sample("construction_and_first_open") {
                let loaded = makeChannels()
                checksum += MediaChannelCategory.group(loaded).count
                checksum += MediaSeriesCatalog(loaded).series.count
            }
            sample("classification") {
                for channel in channels {
                    checksum += channel.isLive ? 1 : 0
                    checksum += channel.isAudio ? 1 : 0
                    checksum += channel.isMovie ? 1 : 0
                    checksum += channel.isDownloadableVideo ? 1 : 0
                }
            }
            sample("categories_and_series") {
                checksum += MediaChannelCategory.group(channels).count
                checksum += MediaSeriesCatalog(channels).series.count
            }
            sample("search_and_sort") {
                let matches = channels.filter { $0.title.localizedStandardContains("Title") && $0.isMovie }
                checksum += MediaLibrarySort.titleAscending.sorted(matches, title: { $0.title }, addedAt: { $0.metadata.addedAt }).count
            }
            guard checksum > 0 else { fatalError("Benchmark was optimized away") }
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
