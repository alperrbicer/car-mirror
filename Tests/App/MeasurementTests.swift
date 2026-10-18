import XCTest
@testable import CarMirror

@MainActor
final class MeasurementTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        super.setUp()
        suite = "MeasurementTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil; suite = nil
        super.tearDown()
    }
    func testDefaultOffAndAnalyticsConsentDoesNotEnableCrashReports() {
        let backend = FakeMeasurementBackend()
        let service = AppMeasurement(defaults: defaults, backend: backend)
        service.start()
        let event = MeasurementEvent(name: .sourceSave, outcome: .success, sourceKind: .xtream, operation: .add)
        service.record(event)
        service.failure(.sourceSave, error: NSError(domain: NSURLErrorDomain, code: -1001))
        XCTAssertTrue(backend.events.isEmpty)
        XCTAssertTrue(backend.failures.isEmpty)
        defaults.set(true, forKey: "analytics.enabled")
        service.record(event)
        service.failure(.sourceSave, error: NSError(domain: NSURLErrorDomain, code: -1001))
        XCTAssertEqual(backend.events, [event])
        XCTAssertTrue(backend.failures.isEmpty)
        backend.finishChecking(true)
        XCTAssertEqual(backend.sent, 0)
        XCTAssertEqual(backend.deleted, 1)
        defaults.set(false, forKey: "analytics.enabled")
        service.record(event)
        XCTAssertEqual(backend.events.count, 1)
    }
    func testCrashConsentDoesNotEnableAnalyticsAndStripsSensitiveErrorFields() {
        let backend = FakeMeasurementBackend()
        let service = AppMeasurement(defaults: defaults, backend: backend)
        service.start()
        service.setCrashReportsEnabled(true)
        service.record(MeasurementEvent(name: .paywallView, outcome: .success))
        service.failure(.playbackError, error: NSError(domain: NSURLErrorDomain, code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "password=secret", NSURLErrorFailingURLStringErrorKey: "https://user:secret@example.com/private"]))
        XCTAssertTrue(backend.events.isEmpty)
        XCTAssertEqual(backend.failures.count, 1)
        XCTAssertEqual(backend.failures.first?.family, .url)
        XCTAssertEqual(backend.failures.first?.code, -1001)
        let encoded = String(data: try! JSONEncoder().encode(backend.failures), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("secret"))
        XCTAssertFalse(encoded.contains("example.com"))
    }
    func testOnlyConsentingPreviousSessionsUploadAndRevocationWinsAsyncRace() {
        defaults.set(true, forKey: AppMeasurement.crashConsentKey)
        let first = AppMeasurement(defaults: defaults, backend: FakeMeasurementBackend())
        first.start() // Establish a consenting session.
        let backend = FakeMeasurementBackend()
        let next = AppMeasurement(defaults: defaults, backend: backend)
        next.start()
        next.setCrashReportsEnabled(false)
        next.setCrashReportsEnabled(true)
        backend.finishChecking(true)
        XCTAssertEqual(backend.sent, 0)
        XCTAssertGreaterThanOrEqual(backend.deleted, 1)
        next.failure(.purchase, error: NSError(domain: "sensitive user string", code: 7))
        XCTAssertTrue(backend.failures.isEmpty, "Re-opt-in cannot resurrect a revoked session")
        let thirdBackend = FakeMeasurementBackend()
        let third = AppMeasurement(defaults: defaults, backend: thirdBackend)
        third.start()
        thirdBackend.finishChecking(true)
        XCTAssertEqual(thirdBackend.sent, 0)
        XCTAssertEqual(thirdBackend.deleted, 1)
    }
    func testConsentingSessionUploadsOnceAndDoesNotNeedAnalytics() {
        defaults.set(true, forKey: AppMeasurement.crashConsentKey)
        let previous = AppMeasurement(defaults: defaults, backend: FakeMeasurementBackend())
        previous.start()
        let backend = FakeMeasurementBackend()
        let current = AppMeasurement(defaults: defaults, backend: backend)
        current.start(); current.start()
        backend.finishChecking(true)
        XCTAssertEqual(backend.sent, 1)
        XCTAssertEqual(backend.checks, 1)
        XCTAssertEqual(backend.disabled, 1)
        XCTAssertFalse(defaults.bool(forKey: "analytics.enabled"))
    }
    func testUnavailableFirebaseNeverUploadsOrRecords() {
        let backend = FakeMeasurementBackend(); backend.available = false
        let service = AppMeasurement(defaults: defaults, backend: backend)
        defaults.set(true, forKey: "analytics.enabled")
        service.start(); service.setCrashReportsEnabled(true)
        service.record(MeasurementEvent(name: .paywallView, outcome: .success))
        service.failure(.restore, error: NSError(domain: "test", code: 1))
        XCTAssertEqual(backend.checks, 0)
        XCTAssertEqual(backend.disabled, 0)
        XCTAssertTrue(backend.events.isEmpty && backend.failures.isEmpty)
    }
    func testPlaybackDeduplicatesPlayingAndExcludesPauseTime() {
        var events: [MeasurementEvent] = []; var completions = 0; var uptime = 0.0
        let session = PlaybackMeasurement(record: { events.append($0) }, completed: { completions += 1 }, uptime: { uptime })
        session.begin(route: .phone)
        uptime = 20; session.playing(true); session.playing(true)
        uptime = 50; session.playing(false)
        uptime = 500; session.playing(true)
        uptime = 529; session.finish()
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(events.map(\.outcome), [.started, .success])
        session.finish()
        XCTAssertEqual(events.count, 2)
        session.begin(route: .cast); session.playing(true)
        uptime += 60; session.finish()
        XCTAssertEqual(completions, 1)
    }
    func testFailedAndCancelledPlaybackNeverQualifiesForReview() {
        var events: [MeasurementEvent] = []; var completions = 0; var uptime = 0.0
        let session = PlaybackMeasurement(record: { events.append($0) }, completed: { completions += 1 }, uptime: { uptime })
        session.begin(route: .cast); session.finish(failed: true)
        session.begin(route: .phone); session.finish()
        session.begin(route: .phone); session.playing(true)
        uptime = 300; session.finish(failed: true)
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(events.map(\.outcome), [.started, .failure, .started, .cancelled, .started, .success, .failure])
        XCTAssertEqual(events.last?.name, .playbackError)
    }
    func testReviewLinkDoesNotRequireFirebaseAndRejectsInjectedIdentifiers() {
        XCTAssertEqual(AppReviewStore.reviewURL(appStoreID: "6818560405")?.absoluteString,
                       "https://apps.apple.com/app/id6818560405?action=write-review")
        for value in ["", "$(MIRIVO_APP_STORE_ID)", "123?redirect=example.com", "１２３"] {
            XCTAssertNil(AppReviewStore.reviewURL(appStoreID: value))
        }
    }
    func testReviewHistoryPersistsLocallyWithoutAnalytics() {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let store = AppReviewStore(defaults: defaults, now: { date })
        for _ in 0..<3 { store.completedPlayback(); date += 86_400 }
        date += 5 * 86_400
        XCTAssertTrue(store.eligible(version: "1.0"))
        store.requested(version: "1.0")
        XCTAssertFalse(AppReviewStore(defaults: defaults, now: { date }).eligible(version: "1.0"))
        XCTAssertFalse(defaults.bool(forKey: "analytics.enabled"))
    }
    func testReviewCannotInterruptPlaybackCarPlayBroadcastOrPurchase() {
        XCTAssertTrue(ReviewPromptContext().allowsPrompt)
        for context in [ReviewPromptContext(rootAvailable: false), ReviewPromptContext(foreground: false),
                        ReviewPromptContext(carPlay: true), ReviewPromptContext(broadcasting: true),
                        ReviewPromptContext(modal: true), ReviewPromptContext(playback: true),
                        ReviewPromptContext(pictureInPicture: true), ReviewPromptContext(purchase: true)] {
            XCTAssertFalse(context.allowsPrompt)
        }
    }
}

@MainActor
private final class FakeMeasurementBackend: MeasurementBackend {
    var available = true
    var events: [MeasurementEvent] = []
    var failures: [DiagnosticFailure] = []
    var sent = 0; var deleted = 0; var checks = 0; var disabled = 0
    private var completion: (@MainActor @Sendable (Bool) -> Void)?
    func log(_ event: MeasurementEvent) { events.append(event) }
    func disableAutomaticCrashUploads() { disabled += 1 }
    func checkUnsentReports(_ completion: @escaping @MainActor @Sendable (Bool) -> Void) { checks += 1; self.completion = completion }
    func sendUnsentReports() { sent += 1 }
    func deleteUnsentReports() { deleted += 1 }
    func recordFailure(operation: MeasurementEvent.Name, failure: DiagnosticFailure) { failures.append(failure) }
    func finishChecking(_ available: Bool) { let callback = completion; completion = nil; callback?(available) }
}
