import XCTest
import UserNotifications
@testable import CarMirror

@MainActor
final class CarConnectionReminderTests: XCTestCase {
    func testDefaultOptOutNeverRequestsPermissionOrSchedulesOnConnect() async {
        let fixture = makeFixture()
        await fixture.store.refreshAuthorization()
        fixture.store.connected(sessionID: "car-session")
        await fixture.store.waitForScheduling()
        XCTAssertFalse(fixture.store.enabled)
        XCTAssertEqual(fixture.permission.requests, 0)
        XCTAssertTrue(fixture.scheduler.requests.isEmpty)
    }

    func testExplicitOptInRequestsPermissionAndPersistsWithoutScheduling() async {
        let fixture = makeFixture()
        await fixture.store.setEnabled(true)
        XCTAssertEqual(fixture.permission.requests, 1)
        XCTAssertEqual(fixture.store.authorization, .authorized)
        XCTAssertTrue(fixture.scheduler.requests.isEmpty)
        XCTAssertTrue(fixture.recreatedStore().enabled)
    }

    func testDuplicateConnectAndPreferenceChangesCannotRepeatASession() async {
        let fixture = makeFixture()
        await fixture.store.setEnabled(true)
        fixture.store.connected(sessionID: "car-session")
        fixture.store.connected(sessionID: "car-session")
        await fixture.store.waitForScheduling()
        await fixture.store.setEnabled(false)
        await fixture.store.setEnabled(true)
        fixture.store.connected(sessionID: "car-session")
        await fixture.store.waitForScheduling()
        XCTAssertEqual(fixture.scheduler.requests.count, 1)
        XCTAssertEqual(fixture.permission.requests, 1)
    }

    func testEnablingWhileConnectedAppliesOnlyToNextConnection() async {
        let fixture = makeFixture()
        fixture.store.connected(sessionID: "same-scene")
        await fixture.store.setEnabled(true)
        fixture.store.connected(sessionID: "same-scene")
        await fixture.store.waitForScheduling()
        XCTAssertTrue(fixture.scheduler.requests.isEmpty)
        fixture.store.disconnected(sessionID: "same-scene")
        fixture.store.connected(sessionID: "same-scene")
        await fixture.store.waitForScheduling()
        XCTAssertEqual(fixture.scheduler.requests.count, 1)
    }

    func testDisconnectAllowsOneReminderForNextSessionEvenWhenSceneIsReused() async {
        let fixture = makeFixture()
        await fixture.store.setEnabled(true)
        fixture.store.connected(sessionID: "same-scene")
        await fixture.store.waitForScheduling()
        let first = fixture.scheduler.requests[0].identifier
        fixture.store.disconnected(sessionID: "same-scene")
        fixture.store.connected(sessionID: "same-scene")
        await fixture.store.waitForScheduling()
        XCTAssertEqual(fixture.scheduler.requests.count, 2)
        XCTAssertNotEqual(first, fixture.scheduler.requests[1].identifier)
        XCTAssertTrue(fixture.scheduler.removed.contains(first))
    }

    func testProcessRestartDoesNotRepeatTheSameCarPlaySession() async {
        let fixture = makeFixture()
        await fixture.store.setEnabled(true)
        fixture.store.connected(sessionID: "restored-scene")
        await fixture.store.waitForScheduling()
        let restarted = fixture.recreatedStore()
        restarted.connected(sessionID: "restored-scene")
        await restarted.waitForScheduling()
        XCTAssertEqual(fixture.scheduler.requests.count, 1)
        restarted.disconnected(sessionID: "restored-scene")
        restarted.connected(sessionID: "restored-scene")
        await restarted.waitForScheduling()
        XCTAssertEqual(fixture.scheduler.requests.count, 2)
    }

    func testDeniedOrRevokedPermissionNeverPromptsFromCarPlay() async {
        for status in [UNAuthorizationStatus.denied, .notDetermined] {
            let fixture = makeFixture()
            await fixture.store.setEnabled(true)
            fixture.permission.status = status
            fixture.store.connected(sessionID: "car-session")
            await fixture.store.waitForScheduling()
            XCTAssertEqual(fixture.permission.requests, 1)
            XCTAssertTrue(fixture.scheduler.requests.isEmpty)
            XCTAssertEqual(fixture.store.authorization, status)
        }
    }

    func testPermissionFailureIsVisibleAndCanBeRetriedExplicitly() async {
        let fixture = makeFixture()
        fixture.permission.fail = true
        await fixture.store.setEnabled(true)
        XCTAssertTrue(fixture.store.permissionFailed)
        XCTAssertFalse(fixture.store.requestingPermission)
        fixture.permission.fail = false
        await fixture.store.setEnabled(true)
        XCTAssertFalse(fixture.store.permissionFailed)
        XCTAssertEqual(fixture.store.authorization, .authorized)
    }

    func testOptOutWhileCheckingAuthorizationPreventsScheduling() async {
        let fixture = makeFixture()
        await fixture.store.setEnabled(true)
        fixture.permission.blockNextCheck = true
        fixture.store.connected(sessionID: "car-session")
        while fixture.permission.continuation == nil { await Task.yield() }
        await fixture.store.setEnabled(false)
        fixture.permission.resumeCheck()
        await fixture.store.waitForScheduling()
        XCTAssertTrue(fixture.scheduler.requests.isEmpty)
    }

    func testDisconnectWhileCheckingAuthorizationPreventsScheduling() async {
        let fixture = makeFixture()
        await fixture.store.setEnabled(true)
        fixture.permission.blockNextCheck = true
        fixture.store.connected(sessionID: "car-session")
        while fixture.permission.continuation == nil { await Task.yield() }
        fixture.store.disconnected(sessionID: "car-session")
        fixture.permission.resumeCheck()
        await fixture.store.waitForScheduling()
        XCTAssertTrue(fixture.scheduler.requests.isEmpty)
    }

    func testOptOutRemovesAnInFlightRequestAgainAfterSchedulingCompletes() async {
        let fixture = makeFixture()
        await fixture.store.setEnabled(true)
        fixture.scheduler.blockNext = true
        fixture.store.connected(sessionID: "car-session")
        while fixture.scheduler.continuation == nil { await Task.yield() }
        let identifier = fixture.scheduler.requests[0].identifier
        await fixture.store.setEnabled(false)
        fixture.scheduler.continuation?.resume()
        fixture.scheduler.continuation = nil
        await fixture.store.waitForScheduling()
        XCTAssertEqual(fixture.scheduler.removed.filter { $0 == identifier }.count, 2)
    }

    func testStaleDisconnectDoesNotCancelANewerSession() async {
        let fixture = makeFixture()
        await fixture.store.setEnabled(true)
        fixture.store.connected(sessionID: "old")
        await fixture.store.waitForScheduling()
        fixture.store.connected(sessionID: "new")
        fixture.store.disconnected(sessionID: "old")
        await fixture.store.waitForScheduling()
        XCTAssertEqual(fixture.scheduler.requests.count, 2)
        XCTAssertFalse(fixture.scheduler.removed.contains(fixture.scheduler.requests[1].identifier))
    }

    func testUncertainSchedulingFailureIsNotRetriedWithinTheSession() async {
        let fixture = makeFixture()
        await fixture.store.setEnabled(true)
        fixture.scheduler.fail = true
        fixture.store.connected(sessionID: "car-session")
        await fixture.store.waitForScheduling()
        fixture.store.connected(sessionID: "car-session")
        await fixture.store.waitForScheduling()
        XCTAssertEqual(fixture.scheduler.requests.count, 1)
        fixture.scheduler.fail = false
        fixture.store.disconnected(sessionID: "car-session")
        fixture.store.connected(sessionID: "next-session")
        await fixture.store.waitForScheduling()
        XCTAssertEqual(fixture.scheduler.requests.count, 2)
    }

    func testReminderIsImmediateLocalAndDoesNotOptIntoCarPlayPresentation() {
        let request = CarConnectionReminderStore.makeRequest()
        XCTAssertNil(request.trigger)
        XCTAssertEqual(request.content.title, "Mirivo")
        XCTAssertEqual(request.content.body, L10n.tr("Mirivo araç bağlantısına hazır"))
        XCTAssertTrue(request.content.categoryIdentifier.isEmpty)
        XCTAssertTrue(request.content.userInfo.isEmpty)
        XCTAssertEqual(request.content.interruptionLevel, .active)
        XCTAssertTrue(CarConnectionReminderStore.isReminder(request))
    }

    func testForegroundPresentationAndTapWorkWithoutRemoteAnnouncementOptIn() {
        let fixture = makeFixture()
        let announcements = NotificationStore(client: nil, defaults: fixture.defaults)
        let request = CarConnectionReminderStore.makeRequest()
        XCTAssertFalse(announcements.enabled)
        XCTAssertEqual(announcements.presentationOptions(for: request, carReminderEnabled: true), [.banner, .list, .sound])
        XCTAssertTrue(announcements.presentationOptions(for: request, carReminderEnabled: false).isEmpty)
        announcements.navigate(request: request, carReminderEnabled: false)
        XCTAssertNil(announcements.pendingNavigation)
        announcements.navigate(request: request, carReminderEnabled: true)
        XCTAssertEqual(announcements.pendingNavigation?.route, .home)
        announcements.consumedNavigation()
        let unrelated = UNNotificationRequest(identifier: "unrelated", content: request.content, trigger: nil)
        XCTAssertTrue(announcements.presentationOptions(for: unrelated, carReminderEnabled: true).isEmpty)
        announcements.navigate(request: unrelated, carReminderEnabled: true)
        XCTAssertNil(announcements.pendingNavigation)
    }

    private func makeFixture() -> ReminderFixture {
        let name = "MirivoCarReminderTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return ReminderFixture(defaults: defaults)
    }
}

@MainActor
private struct ReminderFixture {
    let defaults: UserDefaults
    let permission = ReminderPermission()
    let scheduler = ReminderScheduler()
    let store: CarConnectionReminderStore
    init(defaults: UserDefaults) {
        self.defaults = defaults
        store = CarConnectionReminderStore(defaults: defaults, permission: permission, scheduler: scheduler)
    }
    func recreatedStore() -> CarConnectionReminderStore {
        CarConnectionReminderStore(defaults: defaults, permission: permission, scheduler: scheduler)
    }
}

@MainActor
private final class ReminderPermission: NotificationAuthorizationProviding {
    var status: UNAuthorizationStatus = .notDetermined
    var requests = 0
    var fail = false, blockNextCheck = false
    var continuation: CheckedContinuation<Void, Never>?
    func authorizationStatus() async -> UNAuthorizationStatus {
        if blockNextCheck { blockNextCheck = false; await withCheckedContinuation { continuation = $0 } }
        return status
    }
    func requestAuthorization() async throws -> Bool {
        requests += 1
        if fail { throw URLError(.unknown) }
        status = .authorized
        return true
    }
    func resumeCheck() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class ReminderScheduler: CarConnectionReminderScheduling {
    var requests: [UNNotificationRequest] = []
    var removed: [String] = []
    var fail = false, blockNext = false
    var continuation: CheckedContinuation<Void, Never>?
    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
        if blockNext { blockNext = false; await withCheckedContinuation { continuation = $0 } }
        if fail { throw URLError(.timedOut) }
    }
    func remove(identifier: String) { removed.append(identifier) }
}
