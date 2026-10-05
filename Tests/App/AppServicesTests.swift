import XCTest
import Combine
import UserNotifications
@testable import CarMirror

@MainActor
final class AppServicesTests: XCTestCase {
    func testRequiredUpdateReleasesOnNetworkFailureAndRollback() async throws {
        var fail = false, enabled = true
        let store = AppUpdateStore(appStoreID: "123", version: "1") { _ in
            if fail { throw URLError(.notConnectedToInternet) }
            return try JSONEncoder().encode(AppUpdatePolicy(enabled: enabled, minimumVersion: "2", storeURL: "https://apps.apple.com/app/id123"))
        }
        await store.refresh()
        XCTAssertNotNil(store.requiredURL)
        fail = true
        await store.refresh(force: true)
        XCTAssertNil(store.requiredURL)
        XCTAssertTrue(store.checkFailed)
        fail = false
        await store.refresh(force: true)
        XCTAssertNotNil(store.requiredURL)
        enabled = false
        await store.refresh(force: true)
        XCTAssertNil(store.requiredURL)
    }
    func testMissingAndMalformedPoliciesFailOpen() async {
        for bytes in [nil, Data("{}".utf8), Data("not json".utf8)] {
            let store = AppUpdateStore(appStoreID: "123", version: "1") { _ in bytes }
            await store.refresh()
            XCTAssertNil(store.requiredURL)
        }
    }
    func testSuccessfulChecksAreThrottledButManualRetryBypassesIt() async {
        var calls = 0
        let store = AppUpdateStore(appStoreID: "123", version: "1") { _ in calls += 1; return nil }
        await store.refresh(now: Date(timeIntervalSince1970: 1000))
        await store.refresh(now: Date(timeIntervalSince1970: 1001))
        XCTAssertEqual(calls, 1)
        await store.refresh(force: true)
        XCTAssertEqual(calls, 2)
    }

    func testPermissionIsNotRequestedOnLaunchAndReadyRequiresServerAck() async {
        let fixture = makeStore()
        await fixture.store.refresh()
        await fixture.store.waitForSynchronization()
        XCTAssertEqual(fixture.permission.requests, 0)
        XCTAssertFalse(fixture.store.enabled)
        await fixture.store.setEnabled(true)
        XCTAssertEqual(fixture.permission.requests, 1)
        XCTAssertEqual(fixture.store.status, .registering)
        fixture.client.fail = true
        fixture.store.receivedToken("a-firebase-registration-token")
        await fixture.store.waitForSynchronization()
        XCTAssertEqual(fixture.store.status, .failed)
        fixture.client.fail = false
        fixture.store.receivedToken("rotated-firebase-registration-token")
        await fixture.store.waitForSynchronization()
        XCTAssertEqual(fixture.store.status, .active)
        fixture.store.registrationFailed()
        XCTAssertEqual(fixture.store.status, .active, "A late registration error must not replace a completed server registration")
        XCTAssertEqual(fixture.client.tokens.last!, "rotated-firebase-registration-token")
    }
    func testOptOutDuringRegistrationWinsAndFailedRemovalRetries() async {
        let fixture = makeStore()
        await fixture.store.setEnabled(true)
        fixture.client.blockNext = true
        fixture.store.receivedToken("old-firebase-registration-token")
        while fixture.client.continuation == nil { await Task.yield() }
        await fixture.store.setEnabled(false)
        fixture.client.continuation?.resume(); fixture.client.continuation = nil
        await fixture.store.waitForSynchronization()
        XCTAssertNil(fixture.client.tokens.last!)
        XCTAssertEqual(fixture.store.status, .off)
        fixture.client.fail = true
        await fixture.store.setEnabled(false)
        await fixture.store.waitForSynchronization()
        XCTAssertEqual(fixture.store.status, .removalPending)
        fixture.client.fail = false
        await fixture.store.refresh()
        await fixture.store.waitForSynchronization()
        XCTAssertEqual(fixture.store.status, .off)
    }
    func testOpeningSettingsKeepsAcknowledgedRegistrationStable() async {
        let fixture = makeStore()
        await fixture.store.setEnabled(true)
        fixture.store.receivedToken("a-firebase-registration-token")
        await fixture.store.waitForSynchronization()

        var states: [NotificationStore.Status] = []
        let observation = fixture.store.$status.sink { states.append($0) }
        defer { observation.cancel() }
        await fixture.store.refresh()
        await fixture.store.refresh()
        fixture.store.receivedToken("a-firebase-registration-token")
        fixture.store.receivedToken("a-firebase-registration-token")
        await fixture.store.waitForSynchronization()

        XCTAssertEqual(states, [.active], "Reopening settings and duplicate FCM callbacks must not flash the preparing state")
        XCTAssertEqual(fixture.permission.registrations, 1)
        XCTAssertEqual(fixture.client.tokens.count, 1)
    }
    func testOpeningSettingsKeepsAcknowledgedOptOutStable() async {
        let fixture = makeStore()
        await fixture.store.refresh()
        await fixture.store.waitForSynchronization()
        var states: [NotificationStore.Status] = []
        let observation = fixture.store.$status.sink { states.append($0) }
        defer { observation.cancel() }
        await fixture.store.refresh()
        await fixture.store.refresh()
        await fixture.store.waitForSynchronization()
        XCTAssertEqual(states, [.off])
        XCTAssertEqual(fixture.client.tokens.count, 1)
        XCTAssertEqual(fixture.permission.requests, 0)
    }
    func testRepeatedRefreshAndTokenCallbacksShareInFlightRegistration() async {
        let fixture = makeStore()
        await fixture.store.setEnabled(true)
        await fixture.store.refresh()
        XCTAssertEqual(fixture.permission.registrations, 1)

        fixture.client.blockNext = true
        fixture.store.receivedToken("a-firebase-registration-token")
        while fixture.client.continuation == nil { await Task.yield() }
        var states: [NotificationStore.Status] = []
        let observation = fixture.store.$status.sink { states.append($0) }
        defer { observation.cancel() }
        await fixture.store.refresh()
        fixture.store.receivedToken("a-firebase-registration-token")
        fixture.client.continuation?.resume(); fixture.client.continuation = nil
        await fixture.store.waitForSynchronization()

        XCTAssertEqual(states, [.syncing, .active])
        XCTAssertEqual(fixture.permission.registrations, 1)
        XCTAssertEqual(fixture.client.tokens.count, 1)
    }
    func testUnchangedTokenCanRetryAfterFailedSynchronization() async {
        let fixture = makeStore()
        await fixture.store.setEnabled(true)
        fixture.client.fail = true
        fixture.store.receivedToken("a-firebase-registration-token")
        await fixture.store.waitForSynchronization()
        XCTAssertEqual(fixture.store.status, .failed)
        fixture.client.fail = false
        fixture.store.receivedToken("a-firebase-registration-token")
        await fixture.store.waitForSynchronization()
        XCTAssertEqual(fixture.store.status, .active)
        XCTAssertEqual(fixture.client.tokens.count, 2)
    }
    func testReenableDuringRemovalStartsANewDeviceRegistration() async {
        let fixture = makeStore()
        await fixture.store.setEnabled(true)
        fixture.store.receivedToken("old-firebase-registration-token")
        await fixture.store.waitForSynchronization()
        fixture.client.blockNext = true
        await fixture.store.setEnabled(false)
        while fixture.client.continuation == nil { await Task.yield() }

        await fixture.store.setEnabled(true)
        XCTAssertEqual(fixture.permission.registrations, 2)
        fixture.store.receivedToken("new-firebase-registration-token")
        fixture.client.continuation?.resume(); fixture.client.continuation = nil
        await fixture.store.waitForSynchronization()
        XCTAssertEqual(fixture.store.status, .active)
        XCTAssertEqual(fixture.client.tokens.last!, "new-firebase-registration-token")
    }
    func testRevokedPermissionRemovesTokenAndRejectsUnknownNavigation() async {
        let fixture = makeStore()
        await fixture.store.setEnabled(true)
        fixture.store.receivedToken("a-firebase-registration-token")
        await fixture.store.waitForSynchronization()
        fixture.permission.status = .denied
        await fixture.store.refresh()
        await fixture.store.waitForSynchronization()
        XCTAssertNil(fixture.client.tokens.last!)
        XCTAssertEqual(fixture.store.status, .denied)
        fixture.store.navigate(userInfo: ["route": "https://example.com"])
        XCTAssertNil(fixture.store.pendingNavigation)
        fixture.store.navigate(userInfo: ["route": "settings"])
        XCTAssertEqual(fixture.store.pendingNavigation?.route, .settings)
        await fixture.store.setEnabled(false)
        fixture.store.navigate(userInfo: ["route": "library"])
        XCTAssertNil(fixture.store.pendingNavigation)
    }
    func testTopicModeDoesNotRegisterSomeoneWhoNeverOptedIn() async throws {
        let defaults = UserDefaults(suiteName: "MirivoTopicTests.\(UUID())")!
        var calls: [Bool] = []
        let client = TopicPushRegistrationClient(defaults: defaults) { calls.append($0) }
        try await client.synchronize(token: nil, locale: "tr")
        XCTAssertTrue(calls.isEmpty)
        try await client.synchronize(token: "fcm-token", locale: "tr")
        try await client.synchronize(token: nil, locale: "tr")
        XCTAssertEqual(calls, [true, false])
        try await client.synchronize(token: nil, locale: "tr")
        XCTAssertEqual(calls, [true, false])
    }
    func testFailedTopicSubscriptionStillUnsubscribesAfterRestart() async throws {
        let defaults = UserDefaults(suiteName: "MirivoTopicTests.\(UUID())")!
        let failed = TopicPushRegistrationClient(defaults: defaults) { _ in throw URLError(.timedOut) }
        do {
            try await failed.synchronize(token: "fcm-token", locale: "tr")
            XCTFail("Expected subscription timeout")
        } catch {}
        var calls: [Bool] = []
        let restarted = TopicPushRegistrationClient(defaults: defaults) { calls.append($0) }
        try await restarted.synchronize(token: nil, locale: "tr")
        XCTAssertEqual(calls, [false])
    }
    private func makeStore() -> (store: NotificationStore, permission: MockPermission, client: MockRegistration) {
        let defaults = UserDefaults(suiteName: "MirivoNotificationTests.\(UUID())")!
        let permission = MockPermission(), client = MockRegistration()
        return (NotificationStore(client: client, permission: permission, defaults: defaults), permission, client)
    }
}

@MainActor
private final class MockPermission: NotificationPermissionProviding {
    var status: UNAuthorizationStatus = .notDetermined
    var requests = 0
    var registrations = 0
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { requests += 1; status = .authorized; return true }
    func register() { registrations += 1 }
    func unregister() {}
}

@MainActor
private final class MockRegistration: PushRegistering {
    var tokens: [String?] = []
    var fail = false, blockNext = false
    var continuation: CheckedContinuation<Void, Never>?
    func synchronize(token: String?, locale: String) async throws {
        tokens.append(token)
        if blockNext { blockNext = false; await withCheckedContinuation { continuation = $0 } }
        if fail { throw URLError(.notConnectedToInternet) }
    }
}
