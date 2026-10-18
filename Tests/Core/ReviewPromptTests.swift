import XCTest
@testable import MirrorCore

final class ReviewPromptTests: XCTestCase {
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    func testRequiresSevenDaysAndSuccessfulPlaybackOnThreeDifferentDays() {
        var policy = ReviewPromptPolicy(firstUse: first)
        for offset in [0, 1, 2] { policy.completedPlayback(at: first.addingTimeInterval(Double(offset) * 86_400)) }
        XCTAssertFalse(policy.isEligible(at: first.addingTimeInterval(7 * 86_400 - 1), version: "1.0"))
        XCTAssertTrue(policy.isEligible(at: first.addingTimeInterval(7 * 86_400), version: "1.0"))
        var sameDay = ReviewPromptPolicy(firstUse: first)
        for _ in 0..<30 { sameDay.completedPlayback(at: first) }
        XCTAssertFalse(sameDay.isEligible(at: first.addingTimeInterval(30 * 86_400), version: "1.0"))
    }
    func testCooldownVersionAndPersistence() throws {
        var policy = ReviewPromptPolicy(firstUse: first)
        for offset in 0..<10 { policy.completedPlayback(at: first.addingTimeInterval(Double(offset) * 86_400)) }
        XCTAssertEqual(policy.successfulDays.count, 3)
        let requested = first.addingTimeInterval(10 * 86_400)
        policy.requested(at: requested, version: "1.0")
        let restored = try JSONDecoder().decode(ReviewPromptPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertEqual(restored, policy)
        XCTAssertFalse(restored.isEligible(at: requested.addingTimeInterval(400 * 86_400), version: "1.0"))
        XCTAssertFalse(restored.isEligible(at: requested.addingTimeInterval(120 * 86_400 - 1), version: "1.1"))
        XCTAssertTrue(restored.isEligible(at: requested.addingTimeInterval(120 * 86_400), version: "1.1"))
        XCTAssertFalse(restored.isEligible(at: first.addingTimeInterval(-1), version: "1.1"))
        XCTAssertFalse(restored.isEligible(at: requested.addingTimeInterval(400 * 86_400), version: ""))
    }
}
