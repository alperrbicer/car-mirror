import XCTest
@testable import MirrorCore

final class PersonalMediaTests: XCTestCase {
    func testLocalAndAudioMediaAreNeverAdvertisedAsLiveStreams() throws {
        for ext in ["mp4", "MOV", "mkv", "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"] {
            let channel = MediaChannel(title: "Test", url: URL(fileURLWithPath: "/tmp/test.\(ext)"))
            XCTAssertFalse(channel.isLive, ext)
        }
        let audio = MediaChannel(title: "Audio", url: try XCTUnwrap(URL(string: "https://example.com/music.MP3?signature=example")))
        XCTAssertTrue(audio.isAudio)
        XCTAssertFalse(audio.isLive)
        XCTAssertFalse(audio.requiresCompatibilityPlayback)
        XCTAssertTrue(MediaChannel(title: "Audio", url: URL(fileURLWithPath: "/tmp/music.flac")).requiresCompatibilityPlayback)
        // Adding local-file playback must not allow playlists or pasted URLs to access the filesystem.
        XCTAssertThrowsError(try MediaURL.validate("file:///tmp/music.mp3"))
    }

    func testByteRangesSupportSeekingAndRejectMalformedRequests() {
        let first = MediaByteRange.parse("bytes=0-99", size: 1000)
        XCTAssertEqual(first?.start, 0); XCTAssertEqual(first?.end, 99); XCTAssertEqual(first?.length, 100)
        let tail = MediaByteRange.parse("bytes=900-", size: 1000)
        XCTAssertEqual(tail?.start, 900); XCTAssertEqual(tail?.length, 100)
        XCTAssertEqual(MediaByteRange.parse("bytes=-100", size: 1000), tail)
        XCTAssertEqual(MediaByteRange.parse("bytes=900-9999", size: 1000), tail)
        XCTAssertEqual(MediaByteRange.parse("bytes=-9999", size: 1000)?.length, 1000)
        for invalid in ["bytes=1000-", "bytes=9-2", "bytes=-0", "bytes=-", "bytes=+1-2", "bytes=0-1,5-6", "bytes=0-9223372036854775808", "bytes=1e2-", "items=0-1"] {
            XCTAssertNil(MediaByteRange.parse(invalid, size: 1000), invalid)
        }
        XCTAssertNil(MediaByteRange.parse("bytes=0-", size: 0))
    }
}
