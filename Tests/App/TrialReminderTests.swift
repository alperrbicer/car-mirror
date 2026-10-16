import XCTest
import UserNotifications
@testable import CarMirror

@MainActor
final class TrialReminderTests: XCTestCase {
    func testDoesNotAskWithoutVerifiedTrialOrDuringOrdinaryRefresh() async {
        let f = fixture()
        await f.store.refresh(requestPermission: true)
        XCTAssertEqual(f.permission.requests, 0)
        XCTAssertTrue(f.scheduler.requests.isEmpty)
        f.provider.trial = f.trial(days: 7)
        await f.store.refresh()
        XCTAssertEqual(f.permission.requests, 0)
        XCTAssertEqual(f.store.status, .permission)
        XCTAssertTrue(f.scheduler.requests.isEmpty)
    }

    func testWeeklyAndAnnualUseSignedExpiryAndDoNotDuplicateAfterRestart() async throws {
        for days in [3, 7] {
            let f = fixture()
            f.provider.trial = f.trial(days: days)
            await f.store.refresh(requestPermission: true)
            XCTAssertEqual(f.permission.requests, 1)
            XCTAssertEqual(f.store.status, .scheduled)
            let request = try XCTUnwrap(f.scheduler.requests.first)
            let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
            XCTAssertEqual(trigger.timeInterval, Double(days - 2) * 86_400, accuracy: 0.01)
            XCTAssertFalse(trigger.repeats)
            XCTAssertTrue(TrialReminderStore.isReminder(request))
            XCTAssertTrue(request.content.body.contains("$29.99 / year"))
            XCTAssertTrue(request.content.categoryIdentifier.isEmpty)
            await f.store.refresh()
            await f.recreated().refresh()
            XCTAssertEqual(f.scheduler.requests.count, 1)
        }
    }

    func testDenialAndPreferenceOptOutNeverPromiseScheduling() async {
        let f = fixture()
        f.provider.trial = f.trial(days: 3)
        f.permission.status = .denied
        await f.store.refresh(requestPermission: true)
        XCTAssertEqual(f.store.status, .denied)
        XCTAssertEqual(f.permission.requests, 0)
        XCTAssertTrue(f.scheduler.requests.isEmpty)
        await f.store.setEnabled(false)
        XCTAssertFalse(f.recreated().enabled)
        f.permission.status = .authorized
        await f.store.refresh()
        XCTAssertEqual(f.store.status, .off)
        XCTAssertTrue(f.scheduler.requests.isEmpty)
    }

    func testCancellationExpiryAndRevokedPermissionRemovePendingReminder() async throws {
        let f = fixture()
        f.permission.status = .authorized
        f.provider.trial = f.trial(days: 7)
        await f.store.refresh()
        let original = try XCTUnwrap(f.scheduler.requests.first)
        f.provider.trial = nil
        await f.store.refresh()
        XCTAssertTrue(f.scheduler.removed.contains(original.identifier))
        XCTAssertEqual(f.store.status, .idle)
        f.provider.trial = f.trial(days: 3)
        await f.store.refresh()
        f.permission.status = .denied
        await f.store.refresh()
        XCTAssertTrue(f.scheduler.pending.isEmpty)
        XCTAssertEqual(f.store.status, .denied)
    }

    func testLateRestoresNeverSendAnImmediateOrMisdatedReminder() async {
        let f = fixture()
        f.provider.trial = f.trial(days: 1)
        await f.store.refresh(requestPermission: true)
        XCTAssertEqual(f.store.status, .tooLate)
        XCTAssertEqual(f.permission.requests, 0)
        XCTAssertTrue(f.scheduler.requests.isEmpty)
    }

    func testFailedSchedulingCanRetryAndDoesNotReportSuccess() async {
        let f = fixture()
        f.provider.trial = f.trial(days: 7)
        f.permission.status = .authorized
        f.scheduler.fail = true
        await f.store.refresh()
        XCTAssertEqual(f.store.status, .failed)
        XCTAssertTrue(f.scheduler.pending.isEmpty)
        f.scheduler.fail = false
        await f.store.refresh()
        XCTAssertEqual(f.store.status, .scheduled)
        XCTAssertEqual(f.scheduler.pending.count, 1)
    }

    func testOptOutWhileSchedulingCannotLeaveAnOrphanReminder() async {
        let f = fixture()
        f.provider.trial = f.trial(days: 7)
        f.permission.status = .authorized
        f.scheduler.block = true
        let task = Task { await f.store.refresh() }
        while f.scheduler.continuation == nil { await Task.yield() }
        await f.store.setEnabled(false)
        f.scheduler.continuation?.resume()
        await task.value
        XCTAssertTrue(f.scheduler.pending.isEmpty)
        XCTAssertEqual(f.store.status, .off)
    }

    func testTrialReminderPresentationDoesNotRequireMarketingNotifications() async throws {
        let f = fixture()
        f.provider.trial = f.trial(days: 7)
        f.permission.status = .authorized
        await f.store.refresh()
        let request = try XCTUnwrap(f.scheduler.requests.first)
        let announcements = NotificationStore(client: nil, defaults: f.defaults)
        XCTAssertFalse(announcements.enabled)
        XCTAssertEqual(announcements.presentationOptions(for: request, carReminderEnabled: false, trialReminderEnabled: true), [.banner, .list, .sound])
        XCTAssertTrue(announcements.presentationOptions(for: request, carReminderEnabled: true, trialReminderEnabled: false).isEmpty)
    }

    private func fixture() -> TrialFixture {
        let name = "MirivoTrialReminderTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return TrialFixture(defaults: defaults)
    }
}

@MainActor
private struct TrialFixture {
    let defaults: UserDefaults
    let permission = TrialPermission()
    let scheduler = TrialScheduler()
    let provider = TrialProvider()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store: TrialReminderStore
    init(defaults: UserDefaults) {
        self.defaults = defaults
        let date = now
        store = TrialReminderStore(defaults: defaults, permission: permission, scheduler: scheduler, provider: provider, now: { date })
    }
    func trial(days: Int) -> TrialReminder {
        TrialReminder(transactionID: 123, expirationDate: now.addingTimeInterval(Double(days) * 86_400), renewalRate: "$29.99 / year")
    }
    func recreated() -> TrialReminderStore {
        TrialReminderStore(defaults: defaults, permission: permission, scheduler: scheduler, provider: provider, now: { now })
    }
}

@MainActor
private final class TrialPermission: NotificationAuthorizationProviding {
    var status: UNAuthorizationStatus = .notDetermined
    var requests = 0
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool { requests += 1; status = .authorized; return true }
}

@MainActor
private final class TrialProvider: TrialReminderProviding {
    var trial: TrialReminder?
    func activeTrial() async throws -> TrialReminder? { trial }
}

@MainActor
private final class TrialScheduler: TrialReminderScheduling {
    var requests: [UNNotificationRequest] = []
    var removed: [String] = []
    var pending = Set<String>()
    var fail = false, block = false
    var continuation: CheckedContinuation<Void, Never>?
    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
        if block { block = false; await withCheckedContinuation { continuation = $0 } }
        if fail { throw URLError(.timedOut) }
        pending.insert(request.identifier)
    }
    func pendingIdentifiers() async -> Set<String> { pending }
    func remove(identifier: String) { removed.append(identifier); pending.remove(identifier) }
}
