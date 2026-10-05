import XCTest
@testable import MirrorCore

final class AppUpdatePolicyTests: XCTestCase {
    func testVersionsCompareNumericallyAndNormalizeMissingComponents() throws {
        XCTAssertEqual(AppVersion("1"), AppVersion("1.0.0"))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9")), try XCTUnwrap(AppVersion("1.10")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.99.999")), try XCTUnwrap(AppVersion("2")))
        for value in ["", " 1.0", "1..0", "1.0-beta", "-1.0", "1.2.3.4", "999999999999999", "١.٠"] {
            XCTAssertNil(AppVersion(value), value)
        }
    }
    func testOnlyOlderVersionsWithMatchingAppStoreIDAreBlocked() {
        let policy = AppUpdatePolicy(enabled: true, minimumVersion: "1.10", storeURL: "https://apps.apple.com/tr/app/mirivo/id123456")
        XCTAssertNotNil(policy.requiredUpdateURL(currentVersion: "1.9", appStoreID: "123456"))
        for current in ["1.10", "1.10.0", "2.0", "invalid"] {
            XCTAssertNil(policy.requiredUpdateURL(currentVersion: current, appStoreID: "123456"))
        }
        for id in ["", "000", "id123456", "12345"] { XCTAssertNil(policy.requiredUpdateURL(currentVersion: "1.9", appStoreID: id)) }
    }
    func testUnsafeAndWrongStoreLinksNeverBlockTheApp() {
        for value in ["", "https://example.com/app/id123", "https://apps.apple.com.evil.test/app/id123", "http://apps.apple.com/app/id123",
                      "https://user@apps.apple.com/app/id123", "https://apps.apple.com:443/app/id123", "https://apps.apple.com/app/id123#fragment",
                      "itms-apps://apps.apple.com/app/id123", "https://apps.apple.com/account/id123"] {
            XCTAssertNil(AppUpdatePolicy(enabled: true, minimumVersion: "2", storeURL: value).requiredUpdateURL(currentVersion: "1", appStoreID: "123"), value)
        }
        XCTAssertNil(AppUpdatePolicy(schemaVersion: 2, enabled: true, minimumVersion: "2", storeURL: "https://apps.apple.com/app/id123")
            .requiredUpdateURL(currentVersion: "1", appStoreID: "123"))
        XCTAssertNil(AppUpdatePolicy(enabled: false, minimumVersion: "2", storeURL: "https://apps.apple.com/app/id123")
            .requiredUpdateURL(currentVersion: "1", appStoreID: "123"))
    }
    func testPushRoutesNeverAllowURLsOrMediaCommands() {
        XCTAssertEqual(NotificationRoute(rawValue: "library"), .library)
        for value in ["https://example.com", "play", "mirivo://settings", "../settings", "LIBRARY"] { XCTAssertNil(NotificationRoute(rawValue: value)) }
    }
}
